#!/usr/bin/env python3
"""ORACLE : calcul du score d'opportunité.

Le principe : chercher ce qui ACCÉLÈRE, pas ce qui est gros. Un jeu à 200 000 joueurs, c'est trop
tard. Un jeu à 4 000 qui a triplé en 72 heures, c'est une fenêtre de 10 à 25 jours.

    OpportunityScore = w1*accélération + w2*vélocité + w3*(1 - saturation)
                     + w4*facilité_de_production + w5*signal_externe - w6*âge_de_la_trend

Les poids de départ sont une hypothèse. `predictions.py --fit` les recalibre sur TES résultats
après dix décisions enregistrées : c'est ça qui rend le système impossible à copier.

  python3 features.py --db oracle.db --top 20
  python3 features.py --db oracle.db --webhook "https://discord.com/api/webhooks/..."
"""

import argparse
import json
import math
import os
import sqlite3
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

# Plancher de joueurs simultanés. Sans lui, un jeu à 3 joueurs qui passe à 9 affiche +200 %
# et rafle la première place : c'est le bug trouvé au premier test ("medal hub" à 3 joueurs).
# Ne pas descendre sous 200 sans mesurer.
MIN_CCU = 300

# Fenêtres d'observation. Au-delà de 12 h le signal se dilue dans le cycle jour/nuit.
SHORT_HOURS = 6
LONG_HOURS = 12

DEFAULT_WEIGHTS = {
    "acceleration": 0.35,
    "velocity": 0.20,
    "unsaturation": 0.20,
    "ease": 0.15,
    "external": 0.10,
    "age_penalty": 0.15,
}

# Facilité de production par genre : ce qu'une IA sait produire seule, et vite.
EASE_BY_GENRE = {
    "Simulation": 0.95,
    "Obby": 0.90,
    "Party": 0.85,
    "Puzzle": 0.75,
    "Adventure": 0.70,
    "Survival": 0.65,
    "Roleplay": 0.60,
    "Action": 0.55,
    "Strategy": 0.55,
    "Sports": 0.45,
    "Shooter": 0.40,
    "RPG": 0.35,
}
DEFAULT_EASE = 0.60

# Une trend a une fenêtre : passé 25 jours, les gros studios sont déjà dessus.
IDEAL_AGE_DAYS = 10
MAX_USEFUL_AGE_DAYS = 45

# Nombre de clones publiés à partir duquel un concept est considéré comme saturé.
SATURATED_CLONES = 12


def parse_ts(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def load_weights(db: sqlite3.Connection) -> dict:
    row = db.execute("SELECT weights FROM score_weights ORDER BY version DESC LIMIT 1").fetchone()
    if row is None:
        return dict(DEFAULT_WEIGHTS)
    weights = dict(DEFAULT_WEIGHTS)
    weights.update(json.loads(row["weights"]))
    return weights


def series(db: sqlite3.Connection, universe_id: int, hours: int) -> list[tuple[datetime, int]]:
    rows = db.execute(
        """SELECT ts, playing FROM snapshots
           WHERE universe_id = ? AND playing IS NOT NULL
           ORDER BY ts DESC LIMIT 200""",
        (universe_id,),
    ).fetchall()
    if not rows:
        return []
    points = [(parse_ts(row["ts"]), int(row["playing"])) for row in rows]
    latest = points[0][0]
    window = [(ts, value) for ts, value in points if (latest - ts).total_seconds() <= hours * 3600]
    return sorted(window)


def growth(points: list[tuple[datetime, int]]) -> float | None:
    """Croissance relative entre le premier et le dernier point d'une fenêtre.

    Relative, pas absolue : un jeu qui double de 4 000 à 8 000 compte autant qu'un jeu qui double
    de 40 000 à 80 000. C'est l'accélération qu'on cherche, pas la taille.
    """
    if len(points) < 2:
        return None
    first = points[0][1]
    last = points[-1][1]
    if first < MIN_CCU:
        return None
    hours = (points[-1][0] - points[0][0]).total_seconds() / 3600
    if hours < 0.5:
        return None
    # normalisé par heure pour comparer des fenêtres de durées différentes
    return ((last - first) / first) / hours


def saturation(db: sqlite3.Connection, concept: str) -> tuple[float, int]:
    """Nombre de jeux publiés de la même famille, rapporté à un seuil d'encombrement.

    La saturation est ce qui dit quand NE PAS y aller : c'est la moitié de la valeur d'ORACLE.

    On préfère la mesure par recherche publique (clones.py), qui voit tout le catalogue.
    La base seule ne contient que le haut des classements et sous-estime toujours la saturation.
    """
    row = db.execute(
        """SELECT value, metadata FROM external_signals
           WHERE source = 'search' AND term = ?
           ORDER BY ts DESC LIMIT 1""",
        (concept,),
    ).fetchone()
    if row is not None:
        clones = int(row["value"])
        level = min(1.0, clones / SATURATED_CLONES)
        # un marché où un seul jeu tient tout est plus fermé qu'un marché éclaté
        try:
            concentration = float(json.loads(row["metadata"] or "{}").get("concentration", 0.0))
        except (json.JSONDecodeError, TypeError, ValueError):
            concentration = 0.0
        level = min(1.0, level + 0.3 * concentration)
        return level, clones
    fallback = db.execute("SELECT COUNT(*) AS clones FROM experiences WHERE concept_key = ?", (concept,)).fetchone()
    clones = int(fallback["clones"]) if fallback else 0
    # Sans mesure dédiée, on ne sait pas : on reste au milieu plutôt que d'annoncer "libre".
    return max(0.5, min(1.0, clones / SATURATED_CLONES)), clones


def external_signal(db: sqlite3.Connection, concept: str) -> float:
    """Signal hors plateforme, normalisé 0..1. Absent = 0.5 (neutre), jamais 0.

    Un signal manquant ne doit pas pénaliser un concept : c'est une inconnue, pas un mauvais score.
    """
    row = db.execute(
        """SELECT AVG(velocity) AS velocity FROM external_signals
           WHERE term = ? AND ts >= datetime('now', '-3 days')""",
        (concept,),
    ).fetchone()
    if row is None or row["velocity"] is None:
        return 0.5
    # une vélocité de +100 % sur trois jours vaut 1.0
    return max(0.0, min(1.0, 0.5 + float(row["velocity"]) / 2.0))


def ease_for(genre: str | None) -> float:
    if not genre:
        return DEFAULT_EASE
    return EASE_BY_GENRE.get(genre, DEFAULT_EASE)


def age_days(created_at: str | None, now: datetime) -> float | None:
    if not created_at:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            created = datetime.strptime(created_at, fmt)
            if created.tzinfo is None:
                created = created.replace(tzinfo=timezone.utc)
            return (now - created).total_seconds() / 86400
        except ValueError:
            continue
    return None


def age_factor(days: float | None) -> float:
    """1.0 dans la fenêtre idéale, décroît avant (trop tôt pour juger) et après (trop tard)."""
    if days is None:
        return 0.5
    if days < 2:
        return 0.4          # deux jours de données ne prouvent rien
    if days <= IDEAL_AGE_DAYS:
        return 1.0
    if days >= MAX_USEFUL_AGE_DAYS:
        return 0.0
    return 1.0 - (days - IDEAL_AGE_DAYS) / (MAX_USEFUL_AGE_DAYS - IDEAL_AGE_DAYS)


def sponsored_ratio(db: sqlite3.Connection, universe_id: int) -> float:
    """Part des apparitions en classement qui étaient sponsorisées.

    Un jeu poussé à coups de publicité n'est pas une tendance organique : son score est amorti.
    """
    row = db.execute(
        """SELECT AVG(is_sponsored) AS ratio FROM sort_membership
           WHERE universe_id = ? AND ts >= datetime('now', '-2 days')""",
        (universe_id,),
    ).fetchone()
    if row is None or row["ratio"] is None:
        return 0.0
    return float(row["ratio"])


def score_universe(db: sqlite3.Connection, row: sqlite3.Row, weights: dict, now: datetime) -> dict | None:
    universe_id = int(row["universe_id"])
    short = series(db, universe_id, SHORT_HOURS)
    long_window = series(db, universe_id, LONG_HOURS)
    if not short:
        return None
    latest_ccu = short[-1][1]
    if latest_ccu < MIN_CCU:
        return None

    velocity = growth(short)
    slow = growth(long_window)
    if velocity is None:
        return None
    # accélération = dérivée seconde : la vitesse récente dépasse-t-elle la vitesse de fond ?
    acceleration = velocity - slow if slow is not None else 0.0

    concept = row["concept_key"] or ""
    sat, clones = saturation(db, concept)
    ease = ease_for(row["genre_l1"])
    external = external_signal(db, concept)
    days = age_days(row["created_at"], now)
    age = age_factor(days)
    sponsored = sponsored_ratio(db, universe_id)

    # Compression douce : une croissance de +50 %/h ne doit pas écraser tout le classement.
    def squash(value: float) -> float:
        return math.tanh(value * 4)

    components = {
        "acceleration": squash(acceleration),
        "velocity": squash(velocity),
        "unsaturation": 1.0 - sat,
        "ease": ease,
        "external": external,
        "age_penalty": 1.0 - age,
    }
    score = (
        weights["acceleration"] * components["acceleration"]
        + weights["velocity"] * components["velocity"]
        + weights["unsaturation"] * components["unsaturation"]
        + weights["ease"] * components["ease"]
        + weights["external"] * components["external"]
        - weights["age_penalty"] * components["age_penalty"]
    )
    # un jeu majoritairement sponsorisé n'est pas une tendance organique
    score *= 1.0 - 0.5 * sponsored

    return {
        "universe_id": universe_id,
        "name": row["name"],
        "concept": concept,
        "score": score,
        "ccu": latest_ccu,
        "velocity": velocity,
        "acceleration": acceleration,
        "saturation": sat,
        "clones": clones,
        "ease": ease,
        "external": external,
        "age_days": days,
        "sponsored": sponsored,
        "components": components,
    }


def score_all(db: sqlite3.Connection) -> list[dict]:
    """Tous les univers scorables, triés. Sert au journal de prédictions : un concept écarté doit
    garder ses composantes, sinon la régression n'a rien à apprendre de ce refus."""
    now = datetime.now(timezone.utc)
    weights = load_weights(db)
    rows = db.execute(
        """SELECT e.* FROM experiences e
           WHERE EXISTS (SELECT 1 FROM snapshots s WHERE s.universe_id = e.universe_id)"""
    ).fetchall()
    scored = []
    for row in rows:
        result = score_universe(db, row, weights, now)
        if result:
            scored.append(result)
    scored.sort(key=lambda item: item["score"], reverse=True)
    return scored


def rank(db: sqlite3.Connection, limit: int) -> list[dict]:
    return score_all(db)[:limit]


def persist(db: sqlite3.Connection, results: list[dict]) -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    db.executemany(
        """INSERT INTO opportunity_scores (universe_id, ts, score, velocity, acceleration, saturation,
                                           ease, external, age_days, ccu, clones, components)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(universe_id, ts) DO UPDATE SET score = excluded.score""",
        [
            (
                item["universe_id"], ts, item["score"], item["velocity"], item["acceleration"],
                item["saturation"], item["ease"], item["external"], item["age_days"],
                item["ccu"], item["clones"], json.dumps(item["components"]),
            )
            for item in results
        ],
    )
    db.commit()


def render_table(results: list[dict]) -> str:
    if not results:
        return "aucun candidat : il faut au moins deux points de mesure espacés de 30 min sur des jeux à plus de 300 joueurs."
    lines = [f"{'SCORE':>6} {'CCU':>8} {'VEL/h':>7} {'ACC':>7} {'SAT':>5} {'CLONES':>6} {'ÂGE':>6}  NOM"]
    for item in results:
        age = f"{item['age_days']:.0f}j" if item["age_days"] is not None else "?"
        lines.append(
            f"{item['score']:>6.3f} {item['ccu']:>8} {item['velocity']:>+7.1%} {item['acceleration']:>+7.1%} "
            f"{item['saturation']:>5.2f} {item['clones']:>6} {age:>6}  {item['name'][:40]}"
        )
    return "\n".join(lines)


def post_discord(webhook: str, results: list[dict]) -> None:
    if not results:
        return
    top = results[:5]
    lines = ["**ORACLE — fenêtres ouvertes**", ""]
    for index, item in enumerate(top, start=1):
        age = f"{item['age_days']:.0f} j" if item["age_days"] is not None else "âge inconnu"
        lines.append(
            f"`{index}.` **{item['name'][:48]}** — score {item['score']:.3f}\n"
            f"　{item['ccu']:,} joueurs · vélocité {item['velocity']:+.0%}/h · accélération {item['acceleration']:+.0%} "
            f"· {item['clones']} clone(s) · {age}"
        )
    body = json.dumps({"content": "\n".join(lines)[:1900]}).encode("utf-8")
    request = urllib.request.Request(webhook, data=body, headers={"Content-Type": "application/json"}, method="POST")
    try:
        urllib.request.urlopen(request, timeout=20).read()
    except urllib.error.HTTPError as error:
        print(f"webhook Discord : HTTP {error.code}", file=sys.stderr)
    except urllib.error.URLError as error:
        print(f"webhook Discord injoignable : {error}", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(description="Score d'opportunité ORACLE")
    parser.add_argument("--db", default="oracle.db")
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--webhook", help="webhook Discord pour l'alerte")
    parser.add_argument("--json", action="store_true", help="sortie JSON au lieu du tableau")
    parser.add_argument("--no-persist", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(args.db):
        raise SystemExit(f"base introuvable : {args.db} (lancer ingest.py d'abord)")
    db = sqlite3.connect(args.db)
    db.row_factory = sqlite3.Row

    points = db.execute("SELECT COUNT(DISTINCT ts) AS n FROM snapshots").fetchone()["n"]
    everything = score_all(db)
    results = everything[:args.top]
    if not args.no_persist:
        # on enregistre TOUT, pas seulement le haut du classement : les composantes des concepts
        # écartés sont ce qui apprend à la régression à distinguer un bon d'un mauvais pari.
        persist(db, everything)

    if args.json:
        print(json.dumps(results, ensure_ascii=False, indent=1, default=str))
    else:
        print(render_table(results))
        print(f"\n{points} point(s) de mesure en base, plancher à {MIN_CCU} joueurs, fenêtres {SHORT_HOURS} h / {LONG_HOURS} h")
        if points < 3:
            print("Encore trop tôt : laisser tourner l'ingestion une nuit avant de regarder les chiffres.")
    if args.webhook:
        post_discord(args.webhook, results)
    db.close()


if __name__ == "__main__":
    main()
