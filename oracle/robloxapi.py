#!/usr/bin/env python3
"""Accès aux API publiques Roblox. Stdlib uniquement, aucune clé, aucune donnée non publique.

Règles tenues ici :
  - pause entre les appels et backoff sur 429 (un bannissement d'IP casse tout le système) ;
  - uniquement des endpoints publics documentés ou observés en accès anonyme ;
  - aucune tentative de contourner une authentification : l'endpoint des gamepasses est fermé,
    on laisse le signal de monétisation à NULL plutôt que de forcer.
"""

import json
import time
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "oracle-trend-scout/1.0 (+https://github.com/2Lucid/ytb)"

EXPLORE_SORTS = "https://apis.roblox.com/explore-api/v1/get-sorts"
GAMES_BATCH = "https://games.roblox.com/v1/games"
GAMES_VOTES = "https://games.roblox.com/v1/games/votes"
OMNI_SEARCH = "https://apis.roblox.com/search-api/omni-search"

PAUSE = 1.5           # secondes entre deux appels : bien en dessous des limites observées
MAX_RETRIES = 4
BATCH_SIZE = 50       # l'endpoint batch accepte 100, on reste prudent


class RateLimited(Exception):
    pass


def get_json(url: str, params: dict | None = None, timeout: float = 30) -> dict:
    """GET avec backoff exponentiel sur 429 et sur les erreurs serveur passagères."""
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    delay = 2.0
    last_error: Exception | None = None
    for attempt in range(MAX_RETRIES):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code == 429:
                time.sleep(delay)
                delay *= 2
                continue
            if 500 <= error.code < 600:
                time.sleep(delay)
                delay *= 1.6
                continue
            raise
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
            last_error = error
            time.sleep(delay)
            delay *= 1.6
    raise RateLimited(f"échec après {MAX_RETRIES} tentatives sur {url} : {last_error}")


def fetch_sorts(session_id: str, device: str = "computer", country: str = "all") -> list[dict]:
    """Tous les classements publics : top-trending, up-and-coming, top-playing-now, fun-with-friends.

    `up-and-coming` est la mine d'or : des jeux petits mais qui accélèrent.
    """
    payload = get_json(EXPLORE_SORTS, {"sessionId": session_id, "device": device, "country": country})
    sorts = []
    for entry in payload.get("sorts", []):
        if entry.get("contentType") != "Games":
            continue
        sorts.append({
            "sortId": entry.get("sortId", ""),
            "displayName": entry.get("sortDisplayName", ""),
            "games": entry.get("games", []) or [],
        })
    return sorts


def fetch_details(universe_ids: list[int]) -> dict[int, dict]:
    """Détails par lot : date de création, visites, favoris, créateur, genre."""
    out: dict[int, dict] = {}
    for start in range(0, len(universe_ids), BATCH_SIZE):
        chunk = universe_ids[start:start + BATCH_SIZE]
        payload = get_json(GAMES_BATCH, {"universeIds": ",".join(str(i) for i in chunk)})
        for entry in payload.get("data", []):
            out[int(entry["id"])] = entry
        time.sleep(PAUSE)
    return out


def fetch_votes(universe_ids: list[int]) -> dict[int, dict]:
    """Votes par lot. Complète les classements, qui ne donnent les votes que pour le haut du panier."""
    out: dict[int, dict] = {}
    for start in range(0, len(universe_ids), BATCH_SIZE):
        chunk = universe_ids[start:start + BATCH_SIZE]
        try:
            payload = get_json(GAMES_VOTES, {"universeIds": ",".join(str(i) for i in chunk)})
        except (urllib.error.HTTPError, RateLimited):
            continue
        for entry in payload.get("data", []):
            out[int(entry["id"])] = entry
        time.sleep(PAUSE)
    return out


def search(query: str, session_id: str, page_token: str | None = None) -> tuple[list[dict], str | None]:
    """Recherche publique : sert à compter les clones d'un concept (mesure de saturation)."""
    params = {"searchQuery": query, "sessionId": session_id, "pageType": "all"}
    if page_token:
        params["pageToken"] = page_token
    payload = get_json(OMNI_SEARCH, params)
    games: list[dict] = []
    for group in payload.get("searchResults", []):
        if group.get("contentGroupType") != "Game":
            continue
        for item in group.get("contents", []):
            games.append(item)
    return games, payload.get("nextPageToken")


def count_clones(query: str, session_id: str, max_pages: int = 2) -> int:
    """Nombre de jeux publiés portant le même concept : la saturation dit quand ne PAS y aller."""
    total = 0
    token: str | None = None
    for _ in range(max_pages):
        games, token = search(query, session_id, token)
        total += len(games)
        if not token:
            break
        time.sleep(PAUSE)
    return total


# Signal de monétisation : l'endpoint des gamepasses exige une session authentifiée.
# On ne le force pas. La valeur reste NULL, et `features.py` traite l'absence comme "inconnu",
# jamais comme "zéro" : un signal manquant ne doit pas pénaliser un concept.
MONETISATION_AVAILABLE = False
