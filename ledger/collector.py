#!/usr/bin/env python3
"""LEDGER : collecteur HTTP des événements du jeu.

Le jeu poste des lots JSON sur `/ingest` (voir TelemetryService côté Roblox). Le collecteur les
range en base et calcule les métriques quotidiennes.

AnalyticsService alimente déjà les tableaux de bord Roblox. Ce collecteur sert à ce que Roblox
ne donne pas : l'entonnoir par variante de disposition, le palier où le joueur décroche, et le
réglage automatique de l'économie.

  python3 collector.py serve --db ledger.db --port 8787
  python3 collector.py rollup --db ledger.db
  python3 collector.py report --db ledger.db --days 7
"""

import argparse
import json
import os
import sqlite3
import statistics
import sys
import time
from datetime import datetime, timezone, timedelta
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")
MAX_BODY = 2 * 1024 * 1024

# Correspondance entre le numéro d'étape (Sim/Progression.luau) et son nom lisible.
FUNNEL_STEPS = {
    1: "joined", 2: "plot_claimed", 3: "first_collect", 4: "first_purchase",
    5: "first_upgrader", 6: "act_2", 7: "first_employee", 8: "act_3",
    9: "first_burnout", 10: "first_renaissance", 11: "act_4", 12: "act_5", 13: "first_opa",
}


def connect(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path, check_same_thread=False)
    db.row_factory = sqlite3.Row
    with open(SCHEMA, encoding="utf-8") as handle:
        db.executescript(handle.read())
    return db


def day_of(ts: int) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d")


def store_events(db: sqlite3.Connection, events: list[dict]) -> int:
    received = int(time.time())
    rows = []
    for event in events:
        name = str(event.get("event", ""))[:64]
        if not name:
            continue
        rows.append((
            int(event.get("placeId", 0) or 0),
            str(event.get("jobId", ""))[:64],
            int(event.get("userId", 0) or 0),
            int(event.get("layout", 0) or 0),
            name,
            float(event.get("value", 1) or 0),
            json.dumps({k: v for k, v in event.items() if k not in ("event", "userId", "layout", "value", "t", "placeId", "jobId")}),
            int(event.get("t", received) or received),
            received,
        ))
    if rows:
        db.executemany(
            """INSERT INTO events (place_id, job_id, user_id, layout, event, value, payload, ts, received)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            rows,
        )
        db.commit()
    return len(rows)


def rollup(db: sqlite3.Connection, days: int = 30) -> dict:
    """Agrège les événements bruts en jours-joueurs, entonnoir, et métriques quotidiennes."""
    since = int((datetime.now(timezone.utc) - timedelta(days=days)).timestamp())

    # jours-joueurs
    db.execute("DELETE FROM player_days WHERE day >= ?", (day_of(since),))
    rows = db.execute(
        """SELECT user_id, layout, event, value, ts FROM events WHERE ts >= ? ORDER BY ts""",
        (since,),
    ).fetchall()
    aggregate: dict[tuple[int, str], dict] = {}
    for row in rows:
        key = (row["user_id"], day_of(row["ts"]))
        entry = aggregate.setdefault(key, {"layout": row["layout"], "seconds": 0, "sessions": 0, "max_act": 1, "purchases": 0, "robux": 0})
        if row["layout"]:
            entry["layout"] = row["layout"]
        name = row["event"]
        if name == "session_end":
            entry["seconds"] += int(row["value"])
            entry["sessions"] += 1
        elif name == "act":
            entry["max_act"] = max(entry["max_act"], int(row["value"]))
        elif name.startswith("devproduct_"):
            entry["purchases"] += 1
            entry["robux"] += int(row["value"])
        elif name.startswith("gamepass_"):
            entry["purchases"] += 1
    db.executemany(
        """INSERT OR REPLACE INTO player_days (user_id, day, layout, seconds, sessions, max_act, purchases, robux)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        [(user, day, e["layout"], e["seconds"], e["sessions"], e["max_act"], e["purchases"], e["robux"])
         for (user, day), e in aggregate.items()],
    )

    # entonnoir : un joueur compte une fois par étape et par jour
    db.execute("DELETE FROM funnel_daily WHERE day >= ?", (day_of(since),))
    funnel = db.execute(
        """SELECT DISTINCT user_id, layout, CAST(json_extract(payload, '$.step') AS INTEGER) AS step, ts
           FROM events WHERE event = 'onboarding' AND ts >= ?""",
        (since,),
    ).fetchall()
    counts: dict[tuple[str, int, int], set] = {}
    for row in funnel:
        if row["step"] is None:
            continue
        counts.setdefault((day_of(row["ts"]), int(row["step"]), row["layout"]), set()).add(row["user_id"])
    db.executemany(
        "INSERT OR REPLACE INTO funnel_daily (day, step, step_name, layout, players) VALUES (?, ?, ?, ?, ?)",
        [(day, step, FUNNEL_STEPS.get(step, str(step)), layout, len(users)) for (day, step, layout), users in counts.items()],
    )

    # métriques quotidiennes
    computed = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    all_days = sorted({day for _, day in aggregate})
    first_seen: dict[int, str] = {}
    for row in db.execute("SELECT user_id, MIN(day) AS first_day FROM player_days GROUP BY user_id"):
        first_seen[row["user_id"]] = row["first_day"]
    played_on: dict[str, set] = {}
    for row in db.execute("SELECT user_id, day FROM player_days"):
        played_on.setdefault(row["day"], set()).add(row["user_id"])

    for day in all_days:
        cohort = {user for user, first in first_seen.items() if first == day}
        next_day = (datetime.strptime(day, "%Y-%m-%d") + timedelta(days=1)).strftime("%Y-%m-%d")
        day_seven = (datetime.strptime(day, "%Y-%m-%d") + timedelta(days=7)).strftime("%Y-%m-%d")
        retention_d1 = len(cohort & played_on.get(next_day, set())) / len(cohort) if cohort and next_day in played_on else None
        retention_d7 = len(cohort & played_on.get(day_seven, set())) / len(cohort) if cohort and day_seven in played_on else None
        durations = [row["seconds"] for row in db.execute("SELECT seconds FROM player_days WHERE day = ? AND seconds > 0", (day,))]
        median = int(statistics.median(durations)) if durations else 0
        totals = db.execute(
            "SELECT COUNT(*) AS players, SUM(purchases > 0) AS payers, SUM(robux) AS robux FROM player_days WHERE day = ?",
            (day,),
        ).fetchone()
        players = totals["players"] or 0
        conversion = (totals["payers"] or 0) / players if players else None
        arpdau = (totals["robux"] or 0) / players if players else None
        db.execute(
            """INSERT OR REPLACE INTO daily_metrics (day, new_players, returning_players, retention_d1, retention_d7,
                                                     median_seconds, conversion_rate, arpdau_robux, computed_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (day, len(cohort), players - len(cohort), retention_d1, retention_d7, median, conversion, arpdau, computed),
        )
    db.commit()
    return {"player_days": len(aggregate), "days": len(all_days), "funnel_rows": len(counts)}


def report(db: sqlite3.Connection, days: int) -> str:
    since = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    lines: list[str] = []
    rows = db.execute("SELECT * FROM daily_metrics WHERE day >= ? ORDER BY day DESC", (since,)).fetchall()
    if not rows:
        return "aucune métrique : lancer `rollup` après avoir reçu des événements."
    lines.append(f"{'JOUR':<12} {'NOUVEAUX':>9} {'REVENUS':>8} {'D1':>6} {'D7':>6} {'SESSION':>8} {'CONV':>6} {'ARPDAU':>7}")
    for row in rows:
        d1 = f"{row['retention_d1']:.1%}" if row["retention_d1"] is not None else "-"
        d7 = f"{row['retention_d7']:.1%}" if row["retention_d7"] is not None else "-"
        conversion = f"{row['conversion_rate']:.1%}" if row["conversion_rate"] is not None else "-"
        arpdau = f"{row['arpdau_robux']:.1f}" if row["arpdau_robux"] is not None else "-"
        session = f"{row['median_seconds'] // 60}:{row['median_seconds'] % 60:02d}"
        lines.append(f"{row['day']:<12} {row['new_players']:>9} {row['returning_players']:>8} {d1:>6} {d7:>6} {session:>8} {conversion:>6} {arpdau:>7}")

    # entonnoir cumulé sur la fenêtre
    funnel = db.execute(
        """SELECT step, step_name, SUM(players) AS players FROM funnel_daily
           WHERE day >= ? GROUP BY step ORDER BY step""",
        (since,),
    ).fetchall()
    if funnel:
        top = funnel[0]["players"] or 1
        lines.append("\nEntonnoir d'entrée (part des joueurs qui atteignent chaque étape) :")
        previous = top
        for row in funnel:
            share = (row["players"] or 0) / top
            drop = 1 - ((row["players"] or 0) / previous) if previous else 0
            flag = "  <- décrochage" if drop > 0.35 else ""
            lines.append(f"  {row['step']:>2}. {row['step_name']:<20} {row['players']:>6} joueurs  {share:>6.1%}  (-{drop:.0%}){flag}")
            previous = row["players"] or 1

    # comparaison des variantes A/B
    layouts = db.execute(
        """SELECT layout, COUNT(DISTINCT user_id) AS players, AVG(seconds) AS seconds, AVG(max_act) AS act
           FROM player_days WHERE day >= ? AND layout > 0 GROUP BY layout ORDER BY layout""",
        (since,),
    ).fetchall()
    if layouts:
        lines.append("\nVariantes de disposition (A/B) :")
        for row in layouts:
            lines.append(f"  variante {row['layout']} : {row['players']:>5} joueurs, session moyenne {row['seconds'] / 60:.1f} min, acte moyen {row['act']:.2f}")
    return "\n".join(lines)


class Handler(BaseHTTPRequestHandler):
    db: sqlite3.Connection
    key: str

    def _reply(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:  # noqa: N802 - imposé par BaseHTTPRequestHandler
        if self.path.rstrip("/") != "/ingest":
            self._reply(404, {"error": "chemin inconnu"})
            return
        length = int(self.headers.get("Content-Length", 0) or 0)
        if length <= 0 or length > MAX_BODY:
            self._reply(413, {"error": "corps absent ou trop gros"})
            return
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except json.JSONDecodeError:
            self._reply(400, {"error": "JSON invalide"})
            return
        if self.key and payload.get("key") != self.key:
            self._reply(403, {"error": "clé de flux invalide"})
            return
        events = payload.get("events", [])
        if not isinstance(events, list):
            self._reply(400, {"error": "events doit être une liste"})
            return
        stored = store_events(self.db, events[:1000])
        self._reply(200, {"stored": stored})

    def do_GET(self) -> None:  # noqa: N802
        if self.path.rstrip("/") == "/health":
            self._reply(200, {"ok": True})
            return
        self._reply(404, {"error": "chemin inconnu"})

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write(f"{self.address_string()} {fmt % args}\n")


def serve(db: sqlite3.Connection, host: str, port: int, key: str) -> None:
    Handler.db = db
    Handler.key = key
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"collecteur LEDGER sur http://{host}:{port}/ingest (clé de flux : {'oui' if key else 'non'})")
    print("dans le jeu : Config/Telemetry.luau -> COLLECTOR_URL")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\narrêt")
    finally:
        server.server_close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Collecteur et rapports LEDGER")
    parser.add_argument("--db", default="ledger.db")
    sub = parser.add_subparsers(dest="command", required=True)

    serve_parser = sub.add_parser("serve", help="recevoir les événements du jeu")
    serve_parser.add_argument("--host", default="0.0.0.0")
    serve_parser.add_argument("--port", type=int, default=8787)
    serve_parser.add_argument("--key", default=os.environ.get("LEDGER_KEY", "american-dream"))

    rollup_parser = sub.add_parser("rollup", help="agréger les événements en métriques")
    rollup_parser.add_argument("--days", type=int, default=30)

    report_parser = sub.add_parser("report", help="afficher le rapport")
    report_parser.add_argument("--days", type=int, default=7)

    args = parser.parse_args()
    db = connect(args.db)
    if args.command == "serve":
        serve(db, args.host, args.port, args.key)
    elif args.command == "rollup":
        print(json.dumps(rollup(db, args.days), ensure_ascii=False))
    elif args.command == "report":
        print(report(db, args.days))
    db.close()


if __name__ == "__main__":
    main()
