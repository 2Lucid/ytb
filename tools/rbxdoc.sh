#!/usr/bin/env bash
# Consulte la doc officielle Roblox (dépôt public Roblox/creator-docs) sans rien inventer.
# Usage :
#   tools/rbxdoc.sh <Classe>                 -> liste les membres (propriétés, méthodes, événements)
#   tools/rbxdoc.sh <Classe> <Membre>        -> détail d'un membre (paramètres, retour, résumé)
#   tools/rbxdoc.sh --enum <Enum>            -> valeurs d'une énumération
#   tools/rbxdoc.sh --guide <chemin>         -> un guide, ex: parts/model-generation
set -euo pipefail
BASE="https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us"
CACHE="${RBXDOC_CACHE:-${TMPDIR:-/tmp}/rbxdoc-cache}"
mkdir -p "$CACHE"

fetch() { # $1 = chemin relatif
  local rel="$1" out="$CACHE/${1//\//__}"
  if [ ! -s "$out" ]; then
    curl -sS --retry 3 --max-time 60 -o "$out" "$BASE/$rel" || { echo "téléchargement impossible : $rel" >&2; exit 2; }
    if head -c 64 "$out" | grep -q "404: Not Found"; then rm -f "$out"; echo "introuvable dans la doc : $rel" >&2; exit 3; fi
  fi
  cat "$out"
}

case "${1:-}" in
  "" ) sed -n 2,7p "$0"; exit 1 ;;
  --enum ) fetch "reference/engine/enums/$2.yaml" | grep -E "^  - name:|^    value:" ;;
  --guide ) fetch "$2.md" ;;
  * )
    if [ -z "${2:-}" ]; then
      fetch "reference/engine/classes/$1.yaml" | grep -E "^(name|inherits|tags|deprecation_message):|^  - name: |^  - [A-Za-z]+$" | sed 's/^  - name: //'
    else
      python3 - "$(fetch "reference/engine/classes/$1.yaml")" "$1" "$2" <<'PY'
import sys
txt, cls, member = sys.argv[1], sys.argv[2], sys.argv[3]
needle = "  - name: %s.%s\n" % (cls, member)
i = txt.find(needle)
if i < 0:
    needle = "  - name: %s:%s\n" % (cls, member); i = txt.find(needle)
if i < 0:
    print("membre introuvable :", member); sys.exit(3)
seg = txt[i:]
j = seg.find("\n  - name: ", 10)
seg = seg if j < 0 else seg[:j]
for line in seg.split("\n"):
    if line.startswith("    code_samples") or line.startswith("      - ") and "GenerationService-" in line:
        continue
    print(line)
PY
    fi ;;
esac
