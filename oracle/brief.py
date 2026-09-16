#!/usr/bin/env python3
"""ORACLE : génération du brief que FORGE transforme en jeu.

C'est le maillon qui ferme la boucle : ORACLE dit quoi produire, FORGE le produit.

Le brief est déterministe et sans modèle de langage : il traduit des chiffres en contraintes de
production. Un LLM peut l'enrichir ensuite (`--prompt` sort le prompt à lui donner), mais le
squelette doit rester reproductible et vérifiable.

  python3 brief.py --db oracle.db --top 1 --out ../forge/briefs/
  python3 brief.py --db oracle.db --concept egg-steal --prompt
"""

import argparse
import json
import os
import re
import sqlite3
from datetime import datetime, timezone

from features import EASE_BY_GENRE, score_all

# Boucle de jeu par genre : ce qui tient la rétention, exprimé en contraintes concrètes.
LOOP_BY_GENRE = {
    "Simulation": {
        "core": "récolter, revendre, améliorer",
        "cycle_seconds": 90,
        "session_minutes": 20,
        "systems": ["monnaie unique", "5 paliers d'amélioration", "sauvegarde DataStore", "classement serveur"],
    },
    "Obby": {
        "core": "franchir, mourir, recommencer plus loin",
        "cycle_seconds": 45,
        "session_minutes": 15,
        "systems": ["points de contrôle", "30 obstacles", "temps au tour", "cosmétiques de traînée"],
    },
    "Party": {
        "core": "manche courte, gagnant, manche suivante",
        "cycle_seconds": 120,
        "session_minutes": 25,
        "systems": ["file d'attente", "6 mini-jeux", "élimination", "vote de carte"],
    },
    "Puzzle": {
        "core": "comprendre, résoudre, débloquer",
        "cycle_seconds": 150,
        "session_minutes": 20,
        "systems": ["30 niveaux", "indices payants en monnaie de jeu", "progression sauvegardée"],
    },
    "Adventure": {
        "core": "explorer, trouver, revenir plus fort",
        "cycle_seconds": 180,
        "session_minutes": 30,
        "systems": ["3 zones", "inventaire", "PNJ de quête", "boss de zone"],
    },
}
DEFAULT_LOOP = LOOP_BY_GENRE["Simulation"]

# Ce que le brief interdit toujours : ce sont des risques de compte, pas des choix de design.
FORBIDDEN = [
    "loot box ou récompense aléatoire payante sans PolicyService et sans probabilités affichées",
    "faux compte à rebours, fausse rareté, fausse pénurie",
    "monnaie intermédiaire qui brouille le prix réel en Robux",
    "payer pour ne pas perdre sa progression",
    "bouton d'achat placé pour provoquer le clic accidentel",
    "relance agressive des gros dépensiers",
]


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug or "concept"


def gather(db: sqlite3.Connection, concept: str | None, top: int) -> list[dict]:
    scored = score_all(db)
    if concept:
        return [item for item in scored if item["concept"] == concept][:1] or [
            {"concept": concept, "name": concept, "score": 0.0, "ccu": 0, "velocity": 0.0,
             "acceleration": 0.0, "saturation": 0.5, "clones": 0, "ease": 0.6, "external": 0.5,
             "age_days": None, "sponsored": 0.0, "components": {}}
        ]
    return scored[:top]


def genre_for(db: sqlite3.Connection, concept: str) -> str:
    row = db.execute(
        """SELECT genre_l1, COUNT(*) AS n FROM experiences
           WHERE concept_key = ? AND genre_l1 IS NOT NULL AND genre_l1 != ''
           GROUP BY genre_l1 ORDER BY n DESC LIMIT 1""",
        (concept,),
    ).fetchone()
    return row["genre_l1"] if row else "Simulation"


def neighbours(db: sqlite3.Connection, concept: str, limit: int = 6) -> list[dict]:
    """Les jeux de la même famille : ce sont eux qu'il faut aller jouer avant de produire."""
    rows = db.execute(
        """SELECT e.name, e.root_place_id, MAX(s.playing) AS ccu, e.created_at
           FROM experiences e JOIN snapshots s ON s.universe_id = e.universe_id
           WHERE e.concept_key = ?
           GROUP BY e.universe_id ORDER BY ccu DESC LIMIT ?""",
        (concept, limit),
    ).fetchall()
    return [
        {"name": row["name"], "placeId": row["root_place_id"], "ccu": row["ccu"],
         "url": f"https://www.roblox.com/games/{row['root_place_id']}" if row["root_place_id"] else None}
        for row in rows
    ]


def verdict(item: dict) -> tuple[str, str]:
    """Décision lisible : y aller, attendre, ou passer. Un brief qui ne tranche pas ne sert à rien."""
    if item["saturation"] >= 0.85:
        return "passer", "marché saturé : trop de clones et un leader qui tient déjà tout le trafic"
    if item["age_days"] is not None and item["age_days"] > 45:
        return "passer", "trend trop ancienne : la fenêtre de 10 à 25 jours est fermée"
    if item["ccu"] < 300:
        return "attendre", "trop peu de joueurs pour que les pourcentages veuillent dire quelque chose"
    if item["acceleration"] <= 0:
        return "attendre", "la croissance ralentit au lieu d'accélérer : ce n'est pas encore une fenêtre"
    if item["sponsored"] > 0.5:
        return "passer", "visibilité achetée, pas organique : rien ne prouve que le jeu tient tout seul"
    if item["score"] >= 0.35 and item["saturation"] < 0.6:
        return "y aller", "accélération réelle, marché encore ouvert"
    return "attendre", "signal présent mais pas assez net pour engager une production"


def build(db: sqlite3.Connection, item: dict) -> dict:
    concept = item["concept"]
    genre = genre_for(db, concept)
    loop = LOOP_BY_GENRE.get(genre, DEFAULT_LOOP)
    call, why = verdict(item)
    words = concept.replace("-", " ")
    return {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "concept": concept,
        "slug": slugify(concept),
        "verdict": {"call": call, "why": why},
        "signal": {
            "score": round(item["score"], 4),
            "ccu": item["ccu"],
            "velocityPerHour": round(item["velocity"], 4),
            "acceleration": round(item["acceleration"], 4),
            "saturation": round(item["saturation"], 3),
            "clones": item["clones"],
            "ageDays": round(item["age_days"], 1) if item["age_days"] is not None else None,
            "sponsoredShare": round(item["sponsored"], 3),
            "externalSignal": round(item["external"], 3),
            "windowDays": [10, 25],
        },
        "production": {
            "genre": genre,
            "ease": EASE_BY_GENRE.get(genre, 0.6),
            "coreLoop": loop["core"],
            "cycleSeconds": loop["cycle_seconds"],
            "targetSessionMinutes": loop["session_minutes"],
            "requiredSystems": loop["systems"],
            "workingTitle": words.title(),
            "assetBudget": {"heroMeshes": 6, "propMeshes": 40, "images": 12, "audioTracks": 6},
            "targetDays": 14,
        },
        "reference": {
            "playFirst": neighbours(db, concept),
            "note": "Jouer 20 minutes à chacun avant de produire : noter l'emplacement des boutons, la distance entre les machines, la vue au spawn.",
        },
        "monetisation": {
            "strategy": "conversion par la valeur",
            "allowed": [
                "cosmétiques visibles par les autres joueurs",
                "gain de temps équitable, tout restant atteignable gratuitement",
                "serveurs privés",
                "première offre à bas prix (le passage de 0 à 1 achat est la marche difficile)",
                "publicité récompensée",
            ],
            "forbidden": FORBIDDEN,
            "policyService": "PolicyService obligatoire avant tout contenu soumis à politique (achat à récompense aléatoire, publicité, partage)",
        },
        "successCriteria": {
            "retentionD1": 0.10,
            "sessionMinutes": 4,
            "decisionAtDays": 21,
            "note": "Sous 10 % de rétention à J+1, ne pas mettre un Robux en publicité. Sous 4 minutes de session, c'est le design qu'il faut reprendre, pas le code.",
        },
    }


def prompt_for(brief: dict) -> str:
    """Prompt à donner à un modèle pour enrichir le brief en spec complète."""
    signal = brief["signal"]
    production = brief["production"]
    references = ", ".join(entry["name"] for entry in brief["reference"]["playFirst"][:4]) or "aucune référence en base"
    return f"""Tu es lead game designer. Écris la spec complète d'un jeu Roblox à partir de ce brief.

Concept : {brief['concept'].replace('-', ' ')}
Genre : {production['genre']}
Boucle : {production['coreLoop']}, cycle de {production['cycleSeconds']} s, session cible de {production['targetSessionMinutes']} min
Signal : {signal['ccu']} joueurs, vélocité {signal['velocityPerHour']:+.1%}/h, {signal['clones']} clone(s), saturation {signal['saturation']:.2f}
Références à étudier : {references}

Contraintes non négociables :
- Serveur autoritatif : aucun calcul de monnaie côté client.
- 60 FPS sur mobile, UI tactile d'abord (40 % des joueurs sont sur téléphone).
- Tous les textes dans une table de chaînes, FR et EN.
- Monétisation par la valeur. Interdits : {'; '.join(brief['monetisation']['forbidden'][:3])}.
- Budget d'assets : {production['assetBudget']['heroMeshes']} meshes héros, {production['assetBudget']['propMeshes']} props, {production['assetBudget']['images']} visuels 2D.
- Livrable en {production['targetDays']} jours.

Rends : la boucle détaillée minute par minute de la première session, le tableau d'économie
(coût, revenu, cadence, temps théorique par palier), la liste des modules à coder, et les
trois chiffres à surveiller la première semaine.
Ne propose aucun mécanisme figurant dans les interdits."""


def main() -> None:
    parser = argparse.ArgumentParser(description="Générateur de brief ORACLE -> FORGE")
    parser.add_argument("--db", default="oracle.db")
    parser.add_argument("--concept", help="forcer un concept précis")
    parser.add_argument("--top", type=int, default=1)
    parser.add_argument("--out", help="dossier où écrire les briefs")
    parser.add_argument("--prompt", action="store_true", help="afficher le prompt d'enrichissement")
    parser.add_argument("--all-verdicts", action="store_true", help="écrire aussi les briefs dont le verdict est 'passer'")
    args = parser.parse_args()

    if not os.path.exists(args.db):
        raise SystemExit(f"base introuvable : {args.db}")
    db = sqlite3.connect(args.db)
    db.row_factory = sqlite3.Row

    items = gather(db, args.concept, args.top)
    if not items:
        raise SystemExit("aucun candidat : lancer ingest.py puis features.py")

    for item in items:
        brief = build(db, item)
        if args.prompt:
            print(prompt_for(brief))
            continue
        if args.out and (brief["verdict"]["call"] != "passer" or args.all_verdicts):
            os.makedirs(args.out, exist_ok=True)
            path = os.path.join(args.out, f"{brief['slug']}.brief.json")
            with open(path, "w", encoding="utf-8") as handle:
                json.dump(brief, handle, ensure_ascii=False, indent=1)
                handle.write("\n")
            print(f"{brief['verdict']['call'].upper():<9} {brief['concept']:<24} score {brief['signal']['score']:.3f}  -> {path}")
        else:
            print(json.dumps(brief, ensure_ascii=False, indent=1))
    db.close()


if __name__ == "__main__":
    main()
