#!/usr/bin/env python3
"""ORACLE : ingestion des classements publics Roblox dans la base de tendances.

À lancer toutes les 15 minutes (cron). Trois points de mesure espacés de 15 minutes suffisent
à calculer une vélocité ; il faut environ 12 heures pour que l'accélération ait un sens.

  python3 ingest.py --db oracle.db
  python3 ingest.py --db oracle.db --devices computer phone --quiet
"""

import argparse
import json
import os
import sqlite3
import sys
import time
import uuid
from datetime import datetime, timezone, timedelta

import robloxapi
from concepts import concept_key

SCHEMA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "schema.sql")


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def quarter_hour(moment: datetime | None = None) -> str:
    """Arrondit au quart d'heure : deux ingestions rapprochées écrasent la même ligne."""
    moment = moment or datetime.now(timezone.utc)
    minute = (moment.minute // 15) * 15
    return moment.replace(minute=minute, second=0, microsecond=0).strftime("%Y-%m-%dT%H:%M:%SZ")


def connect(path: str) -> sqlite3.Connection:
    fresh = not os.path.exists(path)
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    with open(SCHEMA, encoding="utf-8") as handle:
        db.executescript(handle.read())
    if fresh:
        print(f"base créée : {path}")
    return db


def upsert_experience(db: sqlite3.Connection, universe_id: int, game: dict, details: dict | None, seen: str) -> None:
    name = game.get("name") or (details or {}).get("name") or ""
    key = concept_key(name)
    creator = (details or {}).get("creator") or {}
    db.execute(
        """
        INSERT INTO experiences (universe_id, root_place_id, name, creator_id, creator_name, creator_type,
                                 creator_verified, genre_l1, genre_l2, created_at, updated_at, max_players,
                                 content_maturity, concept_key, first_seen, last_seen)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(universe_id) DO UPDATE SET
            name = excluded.name,
            root_place_id = COALESCE(excluded.root_place_id, experiences.root_place_id),
            creator_id = COALESCE(excluded.creator_id, experiences.creator_id),
            creator_name = COALESCE(excluded.creator_name, experiences.creator_name),
            creator_type = COALESCE(excluded.creator_type, experiences.creator_type),
            creator_verified = COALESCE(excluded.creator_verified, experiences.creator_verified),
            genre_l1 = COALESCE(excluded.genre_l1, experiences.genre_l1),
            genre_l2 = COALESCE(excluded.genre_l2, experiences.genre_l2),
            created_at = COALESCE(excluded.created_at, experiences.created_at),
            updated_at = COALESCE(excluded.updated_at, experiences.updated_at),
            max_players = COALESCE(excluded.max_players, experiences.max_players),
            content_maturity = COALESCE(excluded.content_maturity, experiences.content_maturity),
            concept_key = excluded.concept_key,
            last_seen = excluded.last_seen
        """,
        (
            universe_id,
            game.get("rootPlaceId") or (details or {}).get("rootPlaceId"),
            name,
            creator.get("id"),
            creator.get("name"),
            creator.get("type"),
            1 if creator.get("hasVerifiedBadge") else 0,
            game.get("genreL1") or (details or {}).get("genre_l1") or (details or {}).get("genre"),
            game.get("genreL2") or (details or {}).get("genre_l2"),
            (details or {}).get("created"),
            (details or {}).get("updated"),
            (details or {}).get("maxPlayers"),
            game.get("contentMaturity"),
            key,
            seen,
            seen,
        ),
    )


def run(db: sqlite3.Connection, devices: list[str], quiet: bool) -> dict:
    session_id = uuid.uuid4().hex
    started = now_iso()
    bucket = quarter_hour()
    cursor = db.execute("INSERT INTO ingest_runs (started_at) VALUES (?)", (started,))
    run_id = cursor.lastrowid

    games_by_universe: dict[int, dict] = {}
    memberships: list[tuple] = []
    errors = 0

    for device in devices:
        try:
            sorts = robloxapi.fetch_sorts(session_id, device=device)
        except Exception as error:  # noqa: BLE001 - on note et on continue : une source peut fermer
            errors += 1
            print(f"classements {device} indisponibles : {error}", file=sys.stderr)
            continue
        for sort in sorts:
            for rank, game in enumerate(sort["games"], start=1):
                universe_id = int(game.get("universeId", 0) or 0)
                if universe_id <= 0:
                    continue
                games_by_universe.setdefault(universe_id, game)
                memberships.append((universe_id, sort["sortId"], device, rank, 1 if game.get("isSponsored") else 0, bucket))
        time.sleep(robloxapi.PAUSE)

    if not games_by_universe:
        db.execute("UPDATE ingest_runs SET finished_at = ?, errors = ?, note = ? WHERE id = ?", (now_iso(), errors, "aucun classement", run_id))
        db.commit()
        return {"experiences": 0, "snapshots": 0, "errors": errors}

    universe_ids = sorted(games_by_universe)
    if not quiet:
        print(f"{len(universe_ids)} univers repérés, enrichissement par lot…")
    try:
        details = robloxapi.fetch_details(universe_ids)
    except Exception as error:  # noqa: BLE001
        errors += 1
        details = {}
        print(f"détails indisponibles : {error}", file=sys.stderr)
    votes = robloxapi.fetch_votes(universe_ids)

    snapshots = 0
    for universe_id, game in games_by_universe.items():
        detail = details.get(universe_id)
        upsert_experience(db, universe_id, game, detail, bucket)
        vote = votes.get(universe_id, {})
        db.execute(
            """
            INSERT INTO snapshots (universe_id, ts, playing, visits, favorites, up_votes, down_votes)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(universe_id, ts) DO UPDATE SET
                playing = excluded.playing,
                visits = COALESCE(excluded.visits, snapshots.visits),
                favorites = COALESCE(excluded.favorites, snapshots.favorites),
                up_votes = COALESCE(excluded.up_votes, snapshots.up_votes),
                down_votes = COALESCE(excluded.down_votes, snapshots.down_votes)
            """,
            (
                universe_id,
                bucket,
                game.get("playerCount") or (detail or {}).get("playing"),
                (detail or {}).get("visits"),
                (detail or {}).get("favoritedCount"),
                vote.get("upVotes") or game.get("totalUpVotes"),
                vote.get("downVotes") or game.get("totalDownVotes"),
            ),
        )
        snapshots += 1

    db.executemany(
        """INSERT INTO sort_membership (universe_id, sort_id, device, rank, is_sponsored, ts)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(universe_id, sort_id, device, ts) DO UPDATE SET rank = excluded.rank, is_sponsored = excluded.is_sponsored""",
        memberships,
    )
    db.execute(
        "UPDATE ingest_runs SET finished_at = ?, experiences = ?, snapshots = ?, errors = ? WHERE id = ?",
        (now_iso(), len(games_by_universe), snapshots, errors, run_id),
    )
    db.commit()
    return {"experiences": len(games_by_universe), "snapshots": snapshots, "errors": errors, "memberships": len(memberships)}


def prune(db: sqlite3.Connection, days: int) -> int:
    """Supprime les relevés plus vieux que `days` jours : la base reste légère indéfiniment."""
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    removed = db.execute("DELETE FROM snapshots WHERE ts < ?", (cutoff,)).rowcount
    db.execute("DELETE FROM sort_membership WHERE ts < ?", (cutoff,))
    db.commit()
    return removed


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingestion des classements publics Roblox")
    parser.add_argument("--db", default="oracle.db")
    parser.add_argument("--devices", nargs="+", default=["computer", "phone"])
    parser.add_argument("--prune-days", type=int, default=45, help="supprime les relevés plus vieux que N jours")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    db = connect(args.db)
    started = time.time()
    stats = run(db, args.devices, args.quiet)
    if args.prune_days > 0:
        removed = prune(db, args.prune_days)
        if removed and not args.quiet:
            print(f"{removed} relevé(s) ancien(s) supprimé(s)")
    total_snapshots = db.execute("SELECT COUNT(*) FROM snapshots").fetchone()[0]
    distinct_ts = db.execute("SELECT COUNT(DISTINCT ts) FROM snapshots").fetchone()[0]
    if not args.quiet:
        print(json.dumps(stats, ensure_ascii=False))
        print(f"base : {total_snapshots} relevés sur {distinct_ts} point(s) de mesure, en {time.time() - started:.1f}s")
        if distinct_ts < 3:
            print("il faut au moins 3 points (environ 45 min) avant que la vélocité ait un sens, 12 h pour l'accélération")
    db.close()


if __name__ == "__main__":
    main()
