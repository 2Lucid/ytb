#!/usr/bin/env python3
"""ORACLE : signaux hors plateforme (YouTube, Google Trends, TikTok).

C'est le plus gros gain restant : TikTok précède Roblox de 5 à 20 jours. Voir la tendance avant
qu'elle n'arrive sur la plateforme, c'est toute la fenêtre d'avance.

Chaque source est optionnelle et dégradée proprement : sans clé, le worker se saute et le score
traite le signal comme inconnu (0,5), jamais comme mauvais.

Clés (aucune n'est commitée) :
  export YOUTUBE_API_KEY="..."     # console Google Cloud, API YouTube Data v3, quota gratuit
  export TIKTOK_ACCESS_TOKEN="..." # TikTok Research API (demande d'accès nécessaire)

Google Trends n'a pas d'API publique officielle : on utilise l'endpoint que le site appelle
lui-même, avec une pause franche. Si ça casse un jour, le signal passe simplement à inconnu.

  python3 external.py --db oracle.db --sources youtube trends
"""

import argparse
import json
import os
import sqlite3
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone, timedelta

USER_AGENT = "oracle-trend-scout/1.0"
PAUSE = 2.0


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def get_json(url: str, params: dict | None = None, headers: dict | None = None, timeout: float = 30) -> dict:
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    merged = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    merged.update(headers or {})
    request = urllib.request.Request(url, headers=merged)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        body = response.read().decode("utf-8")
    # Google Trends préfixe ses réponses de caractères de garde
    while body and body[0] not in "{[":
        body = body[1:]
    return json.loads(body)


def terms_to_watch(db: sqlite3.Connection, limit: int) -> list[str]:
    """Les concepts qui montent : ce sont eux qu'on va chercher hors plateforme."""
    rows = db.execute(
        """SELECT e.concept_key, MAX(s.playing) AS ccu
           FROM experiences e JOIN snapshots s ON s.universe_id = e.universe_id
           WHERE e.concept_key IS NOT NULL AND e.concept_key != ''
             AND s.ts >= datetime('now', '-2 days')
           GROUP BY e.concept_key ORDER BY ccu DESC LIMIT ?""",
        (limit,),
    ).fetchall()
    return [row["concept_key"] for row in rows]


def previous_value(db: sqlite3.Connection, source: str, term: str) -> float | None:
    row = db.execute(
        "SELECT value FROM external_signals WHERE source = ? AND term = ? ORDER BY ts DESC LIMIT 1",
        (source, term),
    ).fetchone()
    return float(row["value"]) if row else None


def record(db: sqlite3.Connection, source: str, term: str, value: float, metadata: dict) -> float:
    previous = previous_value(db, source, term)
    velocity = 0.0 if previous is None or previous <= 0 else (value - previous) / previous
    db.execute(
        """INSERT INTO external_signals (source, term, ts, value, velocity, metadata)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(source, term, ts) DO UPDATE SET value = excluded.value, velocity = excluded.velocity""",
        (source, term, now_iso(), value, velocity, json.dumps(metadata)),
    )
    return velocity


# ---------------------------------------------------------------- YouTube
def youtube(db: sqlite3.Connection, terms: list[str], quiet: bool) -> int:
    """Vélocité de vues : nombre de vidéos récentes et vues cumulées sur 7 jours."""
    key = os.environ.get("YOUTUBE_API_KEY", "")
    if not key:
        print("YOUTUBE_API_KEY absente : source YouTube ignorée", file=sys.stderr)
        return 0
    published_after = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
    measured = 0
    for term in terms:
        query = f"roblox {term.replace('-', ' ')}"
        try:
            search = get_json(
                "https://www.googleapis.com/youtube/v3/search",
                {"part": "id", "q": query, "type": "video", "maxResults": 25,
                 "publishedAfter": published_after, "key": key},
            )
            video_ids = [item["id"]["videoId"] for item in search.get("items", []) if item.get("id", {}).get("videoId")]
            if not video_ids:
                record(db, "youtube", term, 0.0, {"videos": 0, "query": query})
                measured += 1
                continue
            stats = get_json(
                "https://www.googleapis.com/youtube/v3/videos",
                {"part": "statistics", "id": ",".join(video_ids), "key": key},
            )
            views = sum(int(item.get("statistics", {}).get("viewCount", 0) or 0) for item in stats.get("items", []))
            velocity = record(db, "youtube", term, float(views), {"videos": len(video_ids), "query": query})
            measured += 1
            if not quiet:
                print(f"  youtube {term:<24} {len(video_ids):>3} vidéos/7j, {views:>10,} vues, {velocity:+.0%}")
        except (urllib.error.HTTPError, urllib.error.URLError, KeyError, json.JSONDecodeError) as error:
            print(f"  youtube {term} : {error}", file=sys.stderr)
        time.sleep(PAUSE)
    db.commit()
    return measured


# ---------------------------------------------------------------- Google Trends
def trends(db: sqlite3.Connection, terms: list[str], quiet: bool) -> int:
    """Confirmation : un terme qui monte sur Trends confirme ce que disent les classements."""
    measured = 0
    for term in terms:
        query = term.replace("-", " ")
        try:
            explore = get_json(
                "https://trends.google.com/trends/api/explore",
                {"hl": "en-US", "tz": "0",
                 "req": json.dumps({"comparisonItem": [{"keyword": query, "geo": "", "time": "now 7-d"}],
                                    "category": 0, "property": ""})},
            )
            widget = next((w for w in explore.get("widgets", []) if w.get("id") == "TIMESERIES"), None)
            if widget is None:
                continue
            series = get_json(
                "https://trends.google.com/trends/api/widgetdata/multiline",
                {"hl": "en-US", "tz": "0", "req": json.dumps(widget["request"]), "token": widget["token"]},
            )
            points = [entry["value"][0] for entry in series.get("default", {}).get("timelineData", []) if entry.get("value")]
            if not points:
                continue
            recent = sum(points[-12:]) / max(1, len(points[-12:]))
            velocity = record(db, "trends", term, float(recent), {"points": len(points), "query": query})
            measured += 1
            if not quiet:
                print(f"  trends  {term:<24} intérêt moyen {recent:>5.1f}, {velocity:+.0%}")
        except (urllib.error.HTTPError, urllib.error.URLError, KeyError, StopIteration, json.JSONDecodeError) as error:
            print(f"  trends {term} : indisponible ({type(error).__name__})", file=sys.stderr)
        time.sleep(PAUSE * 2)  # Trends est susceptible : pause franche
    db.commit()
    return measured


# ---------------------------------------------------------------- TikTok
def tiktok(db: sqlite3.Connection, terms: list[str], quiet: bool) -> int:
    """Signal amont : TikTok précède Roblox de 5 à 20 jours.

    Utilise la Research API officielle, qui demande une validation de compte. Sans jeton, on saute :
    aucun scraping, aucune donnée non publique. Un bannissement d'IP casserait tout le système.
    """
    token = os.environ.get("TIKTOK_ACCESS_TOKEN", "")
    if not token:
        print("TIKTOK_ACCESS_TOKEN absent : source TikTok ignorée (demande d'accès sur developers.tiktok.com)", file=sys.stderr)
        return 0
    start = (datetime.now(timezone.utc) - timedelta(days=7)).strftime("%Y%m%d")
    end = datetime.now(timezone.utc).strftime("%Y%m%d")
    measured = 0
    for term in terms:
        query = term.replace("-", " ")
        payload = json.dumps({
            "query": {"and": [{"operation": "IN", "field_name": "keyword", "field_values": [query]}]},
            "start_date": start, "end_date": end, "max_count": 100,
        }).encode("utf-8")
        request = urllib.request.Request(
            "https://open.tiktokapis.com/v2/research/video/query/?fields=id,view_count,like_count",
            data=payload,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json", "User-Agent": USER_AGENT},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                body = json.loads(response.read().decode("utf-8"))
            videos = body.get("data", {}).get("videos", [])
            views = sum(int(video.get("view_count", 0) or 0) for video in videos)
            velocity = record(db, "tiktok", term, float(views), {"videos": len(videos), "query": query})
            measured += 1
            if not quiet:
                print(f"  tiktok  {term:<24} {len(videos):>3} vidéos/7j, {views:>12,} vues, {velocity:+.0%}")
        except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as error:
            print(f"  tiktok {term} : {error}", file=sys.stderr)
        time.sleep(PAUSE)
    db.commit()
    return measured


SOURCES = {"youtube": youtube, "trends": trends, "tiktok": tiktok}


def main() -> None:
    parser = argparse.ArgumentParser(description="Signaux hors plateforme pour ORACLE")
    parser.add_argument("--db", default="oracle.db")
    parser.add_argument("--sources", nargs="+", default=["youtube", "trends"], choices=list(SOURCES))
    parser.add_argument("--limit", type=int, default=15)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(args.db):
        raise SystemExit(f"base introuvable : {args.db}")
    db = sqlite3.connect(args.db)
    db.row_factory = sqlite3.Row
    terms = terms_to_watch(db, args.limit)
    if not terms:
        raise SystemExit("aucun concept à surveiller : lancer ingest.py d'abord")
    print(f"{len(terms)} concept(s) à mesurer sur {', '.join(args.sources)}")
    total = 0
    for name in args.sources:
        total += SOURCES[name](db, terms, args.quiet)
    print(f"{total} relevé(s) enregistré(s)")
    db.close()


if __name__ == "__main__":
    main()
