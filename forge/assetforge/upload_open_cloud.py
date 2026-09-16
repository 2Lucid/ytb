#!/usr/bin/env python3
"""Upload d'assets externes (GLB, PNG, MP3) via l'API Open Cloud Assets.

Sert pour ce que Cube 3D ne fait pas : les 13 assets héros modélisés en détail, les visuels 2D
(logo, thumbnail, affiches, journaux) et l'audio (Suno, ElevenLabs).

Les meshes générés dans Studio par le plugin passent, eux, par CreateAssetAsync : ils n'ont pas
besoin de ce script.

Prérequis :
  - Une clé Open Cloud (create.roblox.com > Open Cloud > API Keys) avec la permission
    `asset:read` et `asset:write`, restreinte à ton IP si possible.
  - export ROBLOX_API_KEY="..."   et   export ROBLOX_CREATOR_ID="<userId ou groupId>"
  - export ROBLOX_CREATOR_TYPE="User"  (ou "Group")

Ne jamais commiter la clé. Ne jamais contourner la modération : un asset refusé est refusé.

Usage :
  python3 upload_open_cloud.py --dir ../../games/american-dream/assets/source
  python3 upload_open_cloud.py --file coffre-art-deco.glb --id MSH_A5_COLL_Vault --type Model
"""

import argparse
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

API = "https://apis.roblox.com/assets/v1/assets"
OPERATIONS = "https://apis.roblox.com/assets/v1/operations/"

# Extension -> (assetType Open Cloud, contentType)
BY_EXTENSION = {
    ".glb": ("Model", "model/gltf-binary"),
    ".fbx": ("Model", "model/fbx"),
    ".png": ("Decal", "image/png"),
    ".jpg": ("Decal", "image/jpeg"),
    ".jpeg": ("Decal", "image/jpeg"),
    ".bmp": ("Decal", "image/bmp"),
    ".tga": ("Decal", "image/tga"),
    ".mp3": ("Audio", "audio/mpeg"),
    ".ogg": ("Audio", "audio/ogg"),
    ".wav": ("Audio", "audio/wav"),
}


def encode_multipart(fields: dict[str, str], file_field: str, filename: str, content: bytes, content_type: str) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts: list[bytes] = []
    for name, value in fields.items():
        parts.append(f"--{boundary}\r\n".encode())
        parts.append(f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode())
        parts.append(value.encode("utf-8"))
        parts.append(b"\r\n")
    parts.append(f"--{boundary}\r\n".encode())
    parts.append(f'Content-Disposition: form-data; name="{file_field}"; filename="{filename}"\r\n'.encode())
    parts.append(f"Content-Type: {content_type}\r\n\r\n".encode())
    parts.append(content)
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def request(url: str, api_key: str, method: str = "GET", body: bytes | None = None, content_type: str | None = None) -> dict:
    headers = {"x-api-key": api_key}
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:500]
        raise SystemExit(f"HTTP {error.code} sur {url}\n{detail}") from error


def wait_for_operation(path: str, api_key: str, timeout: float = 300) -> dict:
    """Open Cloud renvoie une opération longue : on interroge jusqu'à `done`."""
    operation_id = path.rsplit("/", 1)[-1]
    url = OPERATIONS + operation_id
    deadline = time.time() + timeout
    delay = 2.0
    while time.time() < deadline:
        payload = request(url, api_key)
        if payload.get("done"):
            return payload
        time.sleep(delay)
        delay = min(delay * 1.4, 10)
    raise SystemExit(f"opération {operation_id} toujours en cours après {timeout:.0f} s")


def upload(path: str, asset_id_name: str, asset_type: str, api_key: str, creator_id: str, creator_type: str, description: str) -> int:
    with open(path, "rb") as handle:
        content = handle.read()
    extension = os.path.splitext(path)[1].lower()
    content_type = BY_EXTENSION.get(extension, (None, mimetypes.guess_type(path)[0] or "application/octet-stream"))[1]

    creation_context = {
        "assetType": asset_type,
        "displayName": asset_id_name,
        "description": description,
        "creationContext": {"creator": ({"userId": creator_id} if creator_type == "User" else {"groupId": creator_id})},
    }
    # L'API attend le JSON sous la clé "request" et le binaire sous "fileContent".
    request_payload = {
        "assetType": asset_type,
        "displayName": asset_id_name,
        "description": description,
        "creationContext": creation_context["creationContext"],
    }
    body, multipart_type = encode_multipart(
        {"request": json.dumps(request_payload)},
        "fileContent",
        os.path.basename(path),
        content,
        content_type,
    )
    payload = request(API, api_key, method="POST", body=body, content_type=multipart_type)
    operation_path = payload.get("path") or payload.get("operationId", "")
    if not operation_path:
        raise SystemExit(f"réponse inattendue à l'upload : {json.dumps(payload)[:400]}")
    result = wait_for_operation(operation_path, api_key)
    response = result.get("response", {})
    asset_id = response.get("assetId") or response.get("assetVersionId")
    if not asset_id:
        raise SystemExit(f"upload terminé sans identifiant : {json.dumps(result)[:400]}")
    return int(asset_id)


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload d'assets via Open Cloud")
    parser.add_argument("--dir", help="dossier à parcourir ; le nom du fichier sert d'identifiant de manifest")
    parser.add_argument("--file", help="un seul fichier")
    parser.add_argument("--id", help="identifiant de manifest pour --file")
    parser.add_argument("--type", help="Model, Decal ou Audio (déduit de l'extension sinon)")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "results.json"))
    parser.add_argument("--dry-run", action="store_true", help="liste ce qui serait envoyé sans rien envoyer")
    args = parser.parse_args()

    api_key = os.environ.get("ROBLOX_API_KEY", "")
    creator_id = os.environ.get("ROBLOX_CREATOR_ID", "")
    creator_type = os.environ.get("ROBLOX_CREATOR_TYPE", "User")
    if not args.dry_run and (not api_key or not creator_id):
        raise SystemExit("ROBLOX_API_KEY et ROBLOX_CREATOR_ID sont requis (voir l'entête du script)")

    jobs: list[tuple[str, str, str]] = []
    if args.file:
        identifier = args.id or os.path.splitext(os.path.basename(args.file))[0]
        extension = os.path.splitext(args.file)[1].lower()
        asset_type = args.type or BY_EXTENSION.get(extension, ("Model", ""))[0]
        jobs.append((args.file, identifier, asset_type))
    elif args.dir:
        for name in sorted(os.listdir(args.dir)):
            path = os.path.join(args.dir, name)
            extension = os.path.splitext(name)[1].lower()
            if not os.path.isfile(path) or extension not in BY_EXTENSION:
                continue
            jobs.append((path, os.path.splitext(name)[0], BY_EXTENSION[extension][0]))
    else:
        raise SystemExit("préciser --file ou --dir")

    if not jobs:
        print("rien à envoyer")
        return

    results: dict[str, dict] = {}
    if os.path.exists(args.out):
        with open(args.out, encoding="utf-8") as handle:
            results = json.load(handle).get("results", {})

    for path, identifier, asset_type in jobs:
        size = os.path.getsize(path) / 1024
        if args.dry_run:
            print(f"[sec] {identifier:<36} {asset_type:<7} {size:>8.0f} Ko  {path}")
            continue
        print(f"envoi {identifier} ({asset_type}, {size:.0f} Ko)…", flush=True)
        try:
            asset_id = upload(path, identifier, asset_type, api_key, creator_id, creator_type, f"American Dream / {identifier}")
            results[identifier] = {"status": "done", "assetId": asset_id, "reason": "", "triangles": 0, "textured": True}
            print(f"  ok : {asset_id}")
        except SystemExit as error:
            results[identifier] = {"status": "failed", "assetId": 0, "reason": str(error)[:300], "triangles": 0, "textured": False}
            print(f"  échec : {error}", file=sys.stderr)
        time.sleep(1.0)

    if not args.dry_run:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump({"generatedAt": int(time.time()), "results": results}, handle, ensure_ascii=False, indent=1)
            handle.write("\n")
        print(f"\nrapport écrit : {args.out}")
        print("puis : python3 import_results.py")


if __name__ == "__main__":
    main()
