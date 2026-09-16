#!/usr/bin/env python3
"""Réinjecte le rapport du plugin AssetForge dans le dépôt.

Lit `results.json` (copié depuis ServerStorage.AssetForgeResults), met à jour
`games/american-dream/assets/manifest.json` et régénère
`games/american-dream/src/shared/Generated/AssetIds.luau`.

Un identifiant absent ou à 0 reste un greybox dans le jeu : rien ne casse.

Usage :
  python3 import_results.py [--results results.json] [--game ../../games/american-dream]
"""

import argparse
import json
import os
from datetime import datetime, timezone

# Préfixe d'identifiant -> table du registre Luau
TABLE_BY_PREFIX = {
    "MSH_": "meshes",
    "CHAR_": "meshes",
    "TEX_": "images",
    "SFX_": "audio",
    "MUS_": "audio",
    "AMB_": "audio",
    "ANM_": "animations",
}


def table_for(asset_id: str) -> str:
    for prefix, table in TABLE_BY_PREFIX.items():
        if asset_id.startswith(prefix):
            return table
    # SFX_MUS_* et SFX_AMB_* tombent déjà dans audio via SFX_
    return "meshes"


def render_registry(tables: dict[str, dict[str, int]], generated_at: str) -> str:
    lines = [
        "--!strict",
        "-- FICHIER GÉNÉRÉ par forge/assetforge/import_results.py à partir de assets/manifest.json.",
        "-- Ne pas éditer à la main. Un identifiant absent ou à 0 = greybox (part colorée) à la place du mesh.",
        "return {",
        f'\tgeneratedAt = "{generated_at}",',
    ]
    for name in ("meshes", "images", "audio", "animations"):
        entries = tables.get(name, {})
        if not entries:
            lines.append(f"\t{name} = {{}} :: {{ [string]: number }},")
            continue
        lines.append(f"\t{name} = {{")
        for asset_id in sorted(entries):
            lines.append(f'\t\t["{asset_id}"] = {entries[asset_id]},')
        lines.append("\t},")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="Réinjecte le rapport du plugin dans le dépôt")
    parser.add_argument("--results", default=os.path.join(here, "results.json"))
    parser.add_argument("--game", default=os.path.normpath(os.path.join(here, "..", "..", "games", "american-dream")))
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    manifest_path = os.path.join(args.game, "assets", "manifest.json")
    registry_path = os.path.join(args.game, "src", "shared", "Generated", "AssetIds.luau")

    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)

    results: dict[str, dict] = {}
    if os.path.exists(args.results):
        with open(args.results, encoding="utf-8") as handle:
            payload = json.load(handle)
        results = payload.get("results", payload)
    else:
        print(f"aucun rapport à {args.results} : le registre est régénéré depuis le manifest seul")

    updated, failed = 0, 0
    for asset in manifest["assets"]:
        record = results.get(asset["id"])
        if record is None:
            continue
        status = record.get("status", "pending")
        asset_id = int(record.get("assetId", 0) or 0)
        if status == "done" and asset_id > 0:
            if asset.get("assetId") != asset_id:
                updated += 1
            asset["assetId"] = asset_id
            asset["status"] = "done"
            if record.get("triangles"):
                asset["triangles"] = int(record["triangles"])
            asset["textured"] = bool(record.get("textured", False))
        elif status == "failed":
            failed += 1
            asset["status"] = "failed"
            asset["lastError"] = str(record.get("reason", ""))[:300]

    tables: dict[str, dict[str, int]] = {"meshes": {}, "images": {}, "audio": {}, "animations": {}}
    for asset in manifest["assets"]:
        asset_id = int(asset.get("assetId", 0) or 0)
        if asset_id <= 0:
            continue
        kind = asset.get("kind")
        if kind == "image":
            table = "images"
        elif kind == "audio":
            table = "audio"
        elif kind == "animation":
            table = "animations"
        else:
            table = "meshes"
        tables[table][asset["id"]] = asset_id

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    manifest["generatedAt"] = generated_at
    registry = render_registry(tables, generated_at if any(tables.values()) else "never")

    if args.dry_run:
        print(registry)
    else:
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, ensure_ascii=False, indent=1)
            handle.write("\n")
        with open(registry_path, "w", encoding="utf-8") as handle:
            handle.write(registry)

    total_ids = sum(len(entries) for entries in tables.values())
    pending = sum(1 for asset in manifest["assets"] if int(asset.get("assetId", 0) or 0) == 0)
    print(f"manifest : {updated} identifiant(s) mis à jour, {failed} échec(s) noté(s)")
    print(f"registre : {total_ids} identifiant(s) actif(s), {pending} asset(s) encore en greybox")
    for table, entries in tables.items():
        if entries:
            print(f"  {table} : {len(entries)}")


if __name__ == "__main__":
    main()
