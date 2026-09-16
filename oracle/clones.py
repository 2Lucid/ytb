#!/usr/bin/env python3
"""ORACLE : mesure de la saturation réelle par recherche publique.

La saturation calculée sur la seule base est trompeuse : la base ne contient que le haut des
classements, où chaque concept n'a qu'un ou deux représentants. La vraie question est :
combien de jeux publiés portent déjà ce concept ? C'est la recherche publique qui répond.

La saturation est ce qui dit quand NE PAS y aller. C'est la moitié de la valeur d'ORACLE.

À lancer toutes les 6 heures (moins souvent que l'ingestion : la recherche est plus coûteuse).

  python3 clones.py --db oracle.db --limit 40
"""

import argparse
import json
import os
import sqlite3
import time
import uuid
from datetime import datetime, timezone

import robloxapi
from concepts import concept_key, similarity

SOURCE = "search"


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def concepts_to_measure(db: sqlite3.Connection, limit: int) -> list[tuple[str, str]]:
    """Les concepts les plus prometteurs d'abord : ceux qui ont bougé récemment."""
    rows = db.execute(
        """
        SELECT e.concept_key, MAX(e.name) AS name, MAX(s.playing) AS ccu
        FROM experiences e
        JOIN snapshots s ON s.universe_id = e.universe_id
        WHERE e.concept_key IS NOT NULL AND e.concept_key != ''
          AND s.ts >= datetime('now', '-1 day')
        GROUP BY e.concept_key
        ORDER BY ccu DESC
        LIMIT ?
        """,
        (limit,),
    ).fetchall()
    return [(row["concept_key"], row["name"]) for row in rows]


def measure(db: sqlite3.Connection, concept: str, name: str, session_id: str) -> dict:
    """Compte les jeux publiés du même concept, et la part qui accélère encore."""
    query = concept.replace("-", " ")
    games, _ = robloxapi.search(query, session_id)
    # On ne garde que ce qui est vraiment le même concept : la recherche Roblox ratisse large.
    matching = [game for game in games if similarity(game.get("name", ""), name) >= 0.3 or concept_key(game.get("name", "")) == concept]
    clones = len(matching)
    total_ccu = sum(int(game.get("playerCount", 0) or 0) for game in matching)
    leader = max((int(game.get("playerCount", 0) or 0) for game in matching), default=0)
    # Part du marché tenue par le leader : proche de 1 = un seul gagnant, la place est prise.
    concentration = (leader / total_ccu) if total_ccu > 0 else 0.0
    return {
        "clones": clones,
        "total_ccu": total_ccu,
        "leader_ccu": leader,
        "concentration": concentration,
        "sampled": len(games),
    }


def run(db: sqlite3.Connection, limit: int, quiet: bool) -> int:
    session_id = uuid.uuid4().hex
    ts = now_iso()
    measured = 0
    for concept, name in concepts_to_measure(db, limit):
        try:
            stats = measure(db, concept, name, session_id)
        except Exception as error:  # noqa: BLE001 - une recherche qui échoue ne doit pas tuer le passage
            if not quiet:
                print(f"  {concept} : recherche indisponible ({error})")
            continue
        db.execute(
            """INSERT INTO external_signals (source, term, ts, value, velocity, metadata)
               VALUES (?, ?, ?, ?, ?, ?)
               ON CONFLICT(source, term, ts) DO UPDATE SET value = excluded.value, metadata = excluded.metadata""",
            (SOURCE, concept, ts, float(stats["clones"]), None, json.dumps(stats)),
        )
        measured += 1
        if not quiet:
            print(f"  {concept:<28} {stats['clones']:>3} clone(s), {stats['total_ccu']:>8} joueurs cumulés, leader à {stats['concentration']:.0%}")
        time.sleep(robloxapi.PAUSE)
    db.commit()
    return measured


def main() -> None:
    parser = argparse.ArgumentParser(description="Mesure de saturation par recherche publique")
    parser.add_argument("--db", default="oracle.db")
    parser.add_argument("--limit", type=int, default=40)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(args.db):
        raise SystemExit(f"base introuvable : {args.db}")
    db = sqlite3.connect(args.db)
    db.row_factory = sqlite3.Row
    started = time.time()
    measured = run(db, args.limit, args.quiet)
    print(f"{measured} concept(s) mesuré(s) en {time.time() - started:.0f}s")
    db.close()


if __name__ == "__main__":
    main()
