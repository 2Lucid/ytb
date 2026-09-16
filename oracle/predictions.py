#!/usr/bin/env python3
"""ORACLE : journal de prédictions et recalibrage des poids.

C'est l'étape qui rend le système impossible à copier. Le pipeline se duplique en une soirée ;
un historique de tes décisions, y compris celles que tu as écartées, ne se duplique pas.

Enregistrer AUSSI les refus est la moitié du signal : sans eux, la régression n'apprend que sur
les succès et conclut que tout est bon.

  python3 predictions.py --db oracle.db log --concept egg-steal --decision skipped --reason "20 clones, leader à 98%"
  python3 predictions.py --db oracle.db settle --id 3 --peak-ccu 4200 --revenue 15000
  python3 predictions.py --db oracle.db fit
  python3 predictions.py --db oracle.db list
"""

import argparse
import json
import math
import os
import sqlite3
from datetime import datetime, timezone

from features import DEFAULT_WEIGHTS, rank, load_weights

MIN_SAMPLES_TO_FIT = 10


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def connect(path: str) -> sqlite3.Connection:
    if not os.path.exists(path):
        raise SystemExit(f"base introuvable : {path}")
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    return db


def find_components(db: sqlite3.Connection, concept: str) -> tuple[float, dict, int | None]:
    """Dernier score connu pour un concept, avec le détail de ses composantes."""
    row = db.execute(
        """SELECT o.score, o.components, o.universe_id
           FROM opportunity_scores o
           JOIN experiences e ON e.universe_id = o.universe_id
           WHERE e.concept_key = ?
           ORDER BY o.ts DESC, o.score DESC LIMIT 1""",
        (concept,),
    ).fetchone()
    if row is None:
        return 0.0, {}, None
    return float(row["score"]), json.loads(row["components"] or "{}"), row["universe_id"]


def log_decision(db: sqlite3.Connection, concept: str, decision: str, reason: str, score: float | None) -> int:
    predicted, components, universe_id = find_components(db, concept)
    if score is not None:
        predicted = score
    cursor = db.execute(
        """INSERT INTO predictions_log (concept_key, universe_id, decided_at, predicted_score, components, decision, reason)
           VALUES (?, ?, ?, ?, ?, ?, ?)""",
        (concept, universe_id, now_iso(), predicted, json.dumps(components), decision, reason),
    )
    db.commit()
    return int(cursor.lastrowid or 0)


def settle(db: sqlite3.Connection, entry_id: int, peak_ccu: int, revenue: int, notes: str) -> None:
    """Résultat mesuré à J+30. `outcome_score` normalise pour être comparable au score prédit.

    Échelle logarithmique : passer de 100 à 1 000 joueurs vaut autant que de 1 000 à 10 000.
    C'est une loi de puissance, pas une droite.
    """
    outcome = math.log10(max(1, peak_ccu)) / 5.0  # 100 000 joueurs = 1.0
    outcome = max(0.0, min(1.0, outcome))
    db.execute(
        """UPDATE predictions_log
           SET settled_at = ?, peak_ccu = ?, revenue_robux = ?, outcome_score = ?, notes = ?
           WHERE id = ?""",
        (now_iso(), peak_ccu, revenue, outcome, notes, entry_id),
    )
    db.commit()


def fit(db: sqlite3.Connection, apply_weights: bool) -> dict:
    """Régression des moindres carrés sur les décisions jugées.

    Descente de gradient plutôt qu'inversion de matrice : stdlib uniquement, et robuste
    sur un petit échantillon corrélé (ce qui est exactement notre cas au début).
    """
    rows = db.execute(
        """SELECT components, outcome_score FROM predictions_log
           WHERE settled_at IS NOT NULL AND outcome_score IS NOT NULL AND components IS NOT NULL"""
    ).fetchall()
    samples: list[tuple[dict, float]] = []
    for row in rows:
        components = json.loads(row["components"] or "{}")
        if components:
            samples.append((components, float(row["outcome_score"])))
    if len(samples) < MIN_SAMPLES_TO_FIT:
        return {"fitted": False, "samples": len(samples), "needed": MIN_SAMPLES_TO_FIT}

    keys = list(DEFAULT_WEIGHTS)
    weights = dict(DEFAULT_WEIGHTS)
    learning_rate = 0.05
    for _ in range(4000):
        gradients = {key: 0.0 for key in keys}
        for components, target in samples:
            predicted = sum(
                weights[key] * components.get(key, 0.0) * (-1 if key == "age_penalty" else 1)
                for key in keys
            )
            error = predicted - target
            for key in keys:
                sign = -1 if key == "age_penalty" else 1
                gradients[key] += error * components.get(key, 0.0) * sign
        for key in keys:
            weights[key] -= learning_rate * gradients[key] / len(samples)
            # les poids restent positifs : un signal ne doit pas changer de sens par accident
            weights[key] = max(0.0, min(1.5, weights[key]))

    # qualité de l'ajustement
    mean = sum(target for _, target in samples) / len(samples)
    residual, total = 0.0, 0.0
    for components, target in samples:
        predicted = sum(weights[key] * components.get(key, 0.0) * (-1 if key == "age_penalty" else 1) for key in keys)
        residual += (target - predicted) ** 2
        total += (target - mean) ** 2
    r_squared = 1 - residual / total if total > 0 else 0.0

    if apply_weights:
        db.execute(
            "INSERT INTO score_weights (created_at, weights, sample_size, r_squared, note) VALUES (?, ?, ?, ?, ?)",
            (now_iso(), json.dumps(weights), len(samples), r_squared, "régression sur predictions_log"),
        )
        db.commit()
    return {"fitted": True, "samples": len(samples), "weights": weights, "r_squared": r_squared, "applied": apply_weights}


def auto_log_top(db: sqlite3.Connection, limit: int, threshold: float) -> int:
    """Enregistre automatiquement les meilleurs candidats non encore jugés comme `skipped`.

    Sans ça, le journal ne contient que ce que tu as choisi de faire, et la régression n'apprend
    rien des refus. Un refus explicite vaut un essai.
    """
    known = {row["concept_key"] for row in db.execute("SELECT DISTINCT concept_key FROM predictions_log")}
    logged = 0
    for item in rank(db, limit):
        if item["concept"] in known or item["score"] < threshold:
            continue
        reason = f"repéré automatiquement : {item['ccu']} joueurs, vélocité {item['velocity']:+.0%}/h, {item['clones']} clone(s)"
        log_decision(db, item["concept"], "skipped", reason, item["score"])
        known.add(item["concept"])
        logged += 1
    return logged


def main() -> None:
    parser = argparse.ArgumentParser(description="Journal de prédictions ORACLE")
    parser.add_argument("--db", default="oracle.db")
    sub = parser.add_subparsers(dest="command", required=True)

    log_parser = sub.add_parser("log", help="enregistrer une décision")
    log_parser.add_argument("--concept", required=True)
    log_parser.add_argument("--decision", choices=["shipped", "skipped"], required=True)
    log_parser.add_argument("--reason", default="")
    log_parser.add_argument("--score", type=float)

    settle_parser = sub.add_parser("settle", help="renseigner le résultat à J+30")
    settle_parser.add_argument("--id", type=int, required=True)
    settle_parser.add_argument("--peak-ccu", type=int, required=True)
    settle_parser.add_argument("--revenue", type=int, default=0)
    settle_parser.add_argument("--notes", default="")

    fit_parser = sub.add_parser("fit", help="recalibrer les poids sur l'historique")
    fit_parser.add_argument("--apply", action="store_true", help="enregistrer les nouveaux poids")

    auto_parser = sub.add_parser("auto", help="enregistrer les meilleurs candidats non jugés comme refusés")
    auto_parser.add_argument("--limit", type=int, default=10)
    auto_parser.add_argument("--threshold", type=float, default=0.2)

    sub.add_parser("list", help="afficher le journal")

    args = parser.parse_args()
    db = connect(args.db)

    if args.command == "log":
        entry_id = log_decision(db, args.concept, args.decision, args.reason, args.score)
        print(f"décision #{entry_id} enregistrée : {args.concept} -> {args.decision}")
    elif args.command == "settle":
        settle(db, args.id, args.peak_ccu, args.revenue, args.notes)
        print(f"décision #{args.id} jugée : pic {args.peak_ccu} joueurs, {args.revenue} Robux")
    elif args.command == "fit":
        result = fit(db, args.apply)
        if not result["fitted"]:
            print(f"{result['samples']} décision(s) jugée(s) sur {result['needed']} nécessaires.")
            print("Enregistrer chaque concept regardé, refus compris : c'est la moitié du signal.")
        else:
            print(f"ajusté sur {result['samples']} décisions, R² = {result['r_squared']:.3f}")
            for key, value in sorted(result["weights"].items(), key=lambda item: -item[1]):
                print(f"  {key:<14} {value:.3f}  (départ {DEFAULT_WEIGHTS[key]:.3f})")
            if not args.apply:
                print("\nrelancer avec --apply pour enregistrer ces poids")
    elif args.command == "auto":
        logged = auto_log_top(db, args.limit, args.threshold)
        print(f"{logged} concept(s) enregistré(s) comme refusés")
    elif args.command == "list":
        rows = db.execute("SELECT * FROM predictions_log ORDER BY decided_at DESC LIMIT 40").fetchall()
        if not rows:
            print("journal vide. Enregistrer dès le premier concept regardé, y compris les refus.")
        else:
            weights = load_weights(db)
            print(f"poids actifs : " + ", ".join(f"{k}={v:.2f}" for k, v in weights.items()))
            print(f"\n{'ID':>4} {'CONCEPT':<24} {'DÉCISION':<9} {'PRÉDIT':>7} {'RÉSULTAT':>9}  RAISON")
            for row in rows:
                outcome = f"{row['outcome_score']:.3f}" if row["outcome_score"] is not None else "en cours"
                print(f"{row['id']:>4} {row['concept_key'][:24]:<24} {row['decision']:<9} {row['predicted_score']:>7.3f} {outcome:>9}  {(row['reason'] or '')[:44]}")
    db.close()


if __name__ == "__main__":
    main()
