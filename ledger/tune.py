#!/usr/bin/env python3
"""LEDGER : proposition de réglage de l'économie à partir des mesures.

Le principe : les chiffres de la spec sont une hypothèse. Ce job la confronte au réel et propose
un ajustement chiffré. Il n'applique rien tout seul — il ouvre une proposition qu'un humain valide.

Trois diagnostics, dans cet ordre de gravité :

  1. Décrochage dans l'entonnoir  -> un palier coûte trop cher ou arrive trop tôt
  2. Session trop courte          -> la première boucle est trop lente à récompenser
  3. Rétention D1 faible          -> la promesse des dix premières minutes ne tient pas

Un quatrième signal, la comparaison A/B des dispositions, désigne la variante à garder.

  python3 tune.py --db ledger.db --game ../games/american-dream
  python3 tune.py --db ledger.db --apply --proposal 3
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone, timedelta

# Seuils de décision. Ce sont les chiffres qui disent « ce jeu ne décollera pas ».
RETENTION_D1_FLOOR = 0.10      # sous 10 %, ne pas mettre un Robux en publicité
SESSION_SECONDS_FLOOR = 240    # sous 4 minutes, c'est le design, pas le code
FUNNEL_DROP_ALERT = 0.35       # perdre plus d'un tiers des joueurs sur une étape
MAX_COST_CUT = 0.40            # on ne divise jamais un coût par plus que ça d'un coup
MIN_PLAYERS_TO_DECIDE = 50     # en dessous, le bruit domine : on ne touche à rien


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def connect(path: str) -> sqlite3.Connection:
    if not os.path.exists(path):
        raise SystemExit(f"base introuvable : {path}")
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    return db


def window(db: sqlite3.Connection, days: int) -> tuple[str, int]:
    since = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    row = db.execute("SELECT COUNT(DISTINCT user_id) AS players FROM player_days WHERE day >= ?", (since,)).fetchone()
    return since, int(row["players"] or 0)


def funnel_drops(db: sqlite3.Connection, since: str) -> list[dict]:
    rows = db.execute(
        """SELECT step, step_name, SUM(players) AS players FROM funnel_daily
           WHERE day >= ? GROUP BY step ORDER BY step""",
        (since,),
    ).fetchall()
    drops = []
    previous = None
    for row in rows:
        players = int(row["players"] or 0)
        if previous is not None and previous > 0:
            drop = 1 - players / previous
            if drop >= FUNNEL_DROP_ALERT:
                drops.append({"step": int(row["step"]), "name": row["step_name"], "drop": drop,
                              "from": previous, "to": players})
        previous = players
    return drops


def averages(db: sqlite3.Connection, since: str) -> dict:
    row = db.execute(
        """SELECT AVG(retention_d1) AS d1, AVG(retention_d7) AS d7, AVG(median_seconds) AS seconds,
                  AVG(conversion_rate) AS conversion, AVG(arpdau_robux) AS arpdau
           FROM daily_metrics WHERE day >= ?""",
        (since,),
    ).fetchone()
    return {key: (float(row[key]) if row[key] is not None else None) for key in ("d1", "d7", "seconds", "conversion", "arpdau")}


def layout_winner(db: sqlite3.Connection, since: str) -> dict | None:
    """Désigne la variante de disposition à garder. Les chiffres choisissent, pas le goût."""
    rows = db.execute(
        """SELECT layout, COUNT(DISTINCT user_id) AS players, AVG(seconds) AS seconds, AVG(max_act) AS act
           FROM player_days WHERE day >= ? AND layout > 0
           GROUP BY layout HAVING players >= 20 ORDER BY seconds DESC""",
        (since,),
    ).fetchall()
    if len(rows) < 2:
        return None
    best, worst = rows[0], rows[-1]
    if best["seconds"] <= 0 or worst["seconds"] <= 0:
        return None
    lift = best["seconds"] / worst["seconds"] - 1
    if lift < 0.15:
        return None
    return {"winner": int(best["layout"]), "loser": int(worst["layout"]), "lift": lift,
            "players": int(best["players"]), "seconds": float(best["seconds"])}


# Correspondance entre l'étape de l'entonnoir et le paramètre d'économie à corriger.
STEP_TO_KNOB = {
    3: ("Economy.Tiers[1].dropInterval", "cadence", -0.2, "la première récompense arrive trop tard"),
    4: ("Economy.Tiers[1].extraDropperCosts[1]", "coût", -0.3, "le premier achat est hors de portée"),
    5: ("Economy.Tiers[1].upgraderCost", "coût", -0.25, "le premier améliorateur est trop cher"),
    6: ("Economy.Tiers[2].unlockCost", "coût", -0.3, "l'entrée dans l'acte 2 est un mur"),
    7: ("Economy.Tiers[2].employeeCosts[1]", "coût", -0.25, "le premier employé est trop cher"),
    8: ("Economy.Tiers[3].unlockCost", "coût", -0.3, "l'entrée dans l'acte 3 est un mur"),
    11: ("Economy.Tiers[4].unlockCost", "coût", -0.25, "l'entrée dans l'acte 4 est un mur"),
    12: ("Economy.Tiers[5].unlockCost", "coût", -0.2, "l'entrée dans l'acte 5 est un mur"),
}


def read_config(game_dir: str) -> str:
    path = os.path.join(game_dir, "src", "shared", "Config", "Economy.luau")
    if not os.path.exists(path):
        raise SystemExit(f"configuration d'économie introuvable : {path}")
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def current_value(source: str, path: str) -> float | None:
    """Lit une valeur dans Config/Economy.luau. Le chemin ressemble à Economy.Tiers[2].unlockCost."""
    match = re.match(r"Economy\.Tiers\[(\d+)\]\.(\w+)(?:\[(\d+)\])?", path)
    if not match:
        return None
    act, field, index = int(match.group(1)), match.group(2), match.group(3)
    # on isole le bloc du tier concerné
    blocks = re.findall(r"\{\s*\n\s*act = (\d+),(.*?)\n\t\},", source, re.DOTALL)
    for act_number, body in blocks:
        if int(act_number) != act:
            continue
        if index:
            listing = re.search(rf"{field} = \{{([^}}]*)\}}", body)
            if listing:
                values = [v.strip() for v in listing.group(1).split(",") if v.strip()]
                position = int(index) - 1
                if 0 <= position < len(values):
                    try:
                        return float(values[position])
                    except ValueError:
                        return None
            return None
        found = re.search(rf"\b{field} = ([\d.]+)", body)
        if found:
            return float(found.group(1))
    return None


def propose(db: sqlite3.Connection, game_dir: str, days: int) -> dict:
    since, players = window(db, days)
    metrics = averages(db, since)
    drops = funnel_drops(db, since)
    layout = layout_winner(db, since)
    source = read_config(game_dir)

    diagnosis: list[str] = []
    changes: dict[str, dict] = {}
    evidence: dict = {"windowDays": days, "players": players, "metrics": metrics,
                      "funnelDrops": drops, "layout": layout}

    if players < MIN_PLAYERS_TO_DECIDE:
        return {"diagnosis": f"seulement {players} joueur(s) sur {days} jours : trop peu pour décider, on ne touche à rien",
                "changes": {}, "evidence": evidence, "actionable": False}

    # 1. Décrochages dans l'entonnoir : le signal le plus précis
    for drop in drops:
        knob = STEP_TO_KNOB.get(drop["step"])
        if knob is None:
            continue
        path, kind, ratio, why = knob
        value = current_value(source, path)
        if value is None:
            continue
        # plus le décrochage est fort, plus la correction est franche, mais jamais au-delà du plafond
        severity = min(1.0, (drop["drop"] - FUNNEL_DROP_ALERT) / (1 - FUNNEL_DROP_ALERT) + 0.4)
        adjust = max(-MAX_COST_CUT, ratio * severity)
        after = round(value * (1 + adjust), 4)
        if kind == "cadence":
            after = max(0.5, after)
        else:
            after = max(1.0, round(after))
        if after != value:
            changes[path] = {"before": value, "after": after, "why": why,
                             "evidence": f"{drop['drop']:.0%} des joueurs perdus à l'étape « {drop['name']} »"}
            diagnosis.append(f"décrochage de {drop['drop']:.0%} à « {drop['name']} » : {why}")

    # 2. Session trop courte : la première boucle ne récompense pas assez vite
    seconds = metrics["seconds"]
    if seconds is not None and seconds < SESSION_SECONDS_FLOOR and "Economy.Tiers[1].dropInterval" not in changes:
        value = current_value(source, "Economy.Tiers[1].dropInterval")
        if value:
            after = max(0.5, round(value * 0.8, 2))
            changes["Economy.Tiers[1].dropInterval"] = {
                "before": value, "after": after,
                "why": "la première boucle est trop lente à récompenser",
                "evidence": f"session médiane de {seconds / 60:.1f} min (plancher {SESSION_SECONDS_FLOOR / 60:.0f} min)",
            }
            diagnosis.append(f"session médiane de {seconds / 60:.1f} min : c'est le design qu'il faut reprendre, pas le code")

    # 3. Rétention D1 faible : la promesse des dix premières minutes ne tient pas
    d1 = metrics["d1"]
    if d1 is not None and d1 < RETENTION_D1_FLOOR:
        diagnosis.append(
            f"rétention à J+1 de {d1:.1%}, sous le plancher de {RETENTION_D1_FLOOR:.0%} : "
            "ne pas mettre un Robux en publicité tant que ce chiffre n'a pas bougé"
        )
        value = current_value(source, "Economy.Tiers[2].unlockCost")
        if value and "Economy.Tiers[2].unlockCost" not in changes:
            after = max(1.0, round(value * 0.8))
            changes["Economy.Tiers[2].unlockCost"] = {
                "before": value, "after": after,
                "why": "rapprocher le premier changement de décor pour donner une raison de revenir",
                "evidence": f"rétention D1 de {d1:.1%}",
            }

    # 4. La variante gagnante de disposition
    if layout:
        diagnosis.append(
            f"la variante {layout['winner']} tient les joueurs {layout['lift']:.0%} plus longtemps "
            f"que la variante {layout['loser']} : la garder par défaut"
        )

    if not diagnosis:
        diagnosis.append("aucun signal d'alerte : rétention, session et entonnoir dans les clous")

    return {"diagnosis" : " | ".join(diagnosis), "changes": changes, "evidence": evidence,
            "actionable": bool(changes) or layout is not None}


def save(db: sqlite3.Connection, proposal: dict, days: int) -> int:
    cursor = db.execute(
        """INSERT INTO tuning_proposals (created_at, window_days, diagnosis, changes, evidence)
           VALUES (?, ?, ?, ?, ?)""",
        (now_iso(), days, proposal["diagnosis"], json.dumps(proposal["changes"], ensure_ascii=False),
         json.dumps(proposal["evidence"], ensure_ascii=False, default=str)),
    )
    db.commit()
    return int(cursor.lastrowid or 0)


def apply_proposal(db: sqlite3.Connection, proposal_id: int, game_dir: str) -> list[str]:
    """Écrit les changements dans Config/Economy.luau. Les tests d'économie décideront s'ils tiennent."""
    row = db.execute("SELECT * FROM tuning_proposals WHERE id = ?", (proposal_id,)).fetchone()
    if row is None:
        raise SystemExit(f"proposition {proposal_id} introuvable")
    if row["applied"]:
        raise SystemExit(f"proposition {proposal_id} déjà appliquée le {row['applied_at']}")
    changes = json.loads(row["changes"])
    if not changes:
        raise SystemExit("cette proposition ne contient aucun changement")
    path = os.path.join(game_dir, "src", "shared", "Config", "Economy.luau")
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    applied: list[str] = []
    for knob, change in changes.items():
        match = re.match(r"Economy\.Tiers\[(\d+)\]\.(\w+)(?:\[(\d+)\])?", knob)
        if not match:
            continue
        act, field, index = int(match.group(1)), match.group(2), match.group(3)
        before, after = change["before"], change["after"]
        # on ne remplace que dans le bloc du tier visé
        def replace_in_block(text: str) -> str:
            blocks = list(re.finditer(r"\{\s*\n\s*act = (\d+),.*?\n\t\},", text, re.DOTALL))
            for block in blocks:
                if int(block.group(1)) != act:
                    continue
                body = block.group(0)
                if index:
                    listing = re.search(rf"({field} = \{{)([^}}]*)(\}})", body)
                    if not listing:
                        return text
                    values = [v.strip() for v in listing.group(2).split(",") if v.strip()]
                    position = int(index) - 1
                    if not (0 <= position < len(values)):
                        return text
                    values[position] = str(int(after) if float(after).is_integer() else after)
                    new_body = body.replace(listing.group(0), f"{listing.group(1)} {', '.join(values)} {listing.group(3)}")
                else:
                    formatted = str(int(after) if float(after).is_integer() else after)
                    new_body = re.sub(rf"(\b{field} = )[\d.]+", rf"\g<1>{formatted}", body, count=1)
                return text[:block.start()] + new_body + text[block.end():]
            return text
        updated = replace_in_block(source)
        if updated != source:
            source = updated
            applied.append(f"{knob} : {before} -> {after}")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(source)
    db.execute("UPDATE tuning_proposals SET applied = 1, applied_at = ? WHERE id = ?", (now_iso(), proposal_id))
    db.commit()
    return applied


def main() -> None:
    parser = argparse.ArgumentParser(description="Proposition de réglage d'économie LEDGER")
    parser.add_argument("--db", default="ledger.db")
    parser.add_argument("--game", default=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "games", "american-dream")))
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--apply", action="store_true", help="appliquer une proposition existante")
    parser.add_argument("--proposal", type=int, help="identifiant de la proposition à appliquer")
    parser.add_argument("--list", action="store_true", help="lister les propositions")
    args = parser.parse_args()

    db = connect(args.db)
    if args.list:
        for row in db.execute("SELECT id, created_at, applied, diagnosis FROM tuning_proposals ORDER BY id DESC LIMIT 20"):
            mark = "appliquée" if row["applied"] else "en attente"
            print(f"#{row['id']:>3} [{mark:^10}] {row['created_at']}  {row['diagnosis'][:110]}")
        db.close()
        return
    if args.apply:
        if not args.proposal:
            raise SystemExit("préciser --proposal <id>")
        applied = apply_proposal(db, args.proposal, args.game)
        print(f"proposition {args.proposal} appliquée :")
        for line in applied:
            print(f"  {line}")
        print("\nLancer tools/check.sh : les tests d'économie décideront si le réglage tient.")
        db.close()
        return

    proposal = propose(db, args.game, args.days)
    print(f"Diagnostic : {proposal['diagnosis']}\n")
    if proposal["changes"]:
        print(f"{'PARAMÈTRE':<44} {'AVANT':>12} {'APRÈS':>12}  POURQUOI")
        for knob, change in proposal["changes"].items():
            print(f"{knob:<44} {change['before']:>12} {change['after']:>12}  {change['why']}")
        proposal_id = save(db, proposal, args.days)
        print(f"\nProposition #{proposal_id} enregistrée. Pour l'appliquer :")
        print(f"  python3 tune.py --db {args.db} --apply --proposal {proposal_id}")
        print("  bash ../tools/check.sh    # les tests d'économie valident ou refusent")
    else:
        save(db, proposal, args.days)
        print("Aucun changement proposé.")
    db.close()


if __name__ == "__main__":
    main()
