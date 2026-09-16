#!/usr/bin/env bash
# Porte de qualité unique : lint, typecheck strict, tests Lune, build Rojo.
# Usage : tools/check.sh [chemin du jeu]   (défaut : games/american-dream)
set -uo pipefail
GAME="${1:-games/american-dream}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/$GAME" || { echo "jeu introuvable : $GAME"; exit 1; }
fail=0
step() { printf '\n\033[1;34m== %s\033[0m\n' "$1"; }

# Cibles présentes (le dossier plugin n'existe qu'une fois AssetForge installé)
TARGETS="src tests"
[ -d plugin ] && TARGETS="$TARGETS plugin"

step "1/5 selene (lint)"
if command -v selene >/dev/null; then
  selene $TARGETS 2>&1 | tail -40
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
else echo "selene absent (cargo install selene ou rokit install)"; fail=1; fi

step "2/5 rojo sourcemap"
if command -v rojo >/dev/null; then
  rojo sourcemap default.project.json -o sourcemap.json || fail=1
else echo "rojo absent"; fail=1; fi

step "3/5 luau-lsp analyze (typecheck strict + types Roblox)"
if command -v luau-lsp >/dev/null; then
  DEFS="$ROOT/tools/globalTypes.d.luau"
  if [ ! -s "$DEFS" ]; then
    curl -sS --retry 3 --max-time 60 -o "$DEFS" "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau" || echo "types Roblox non téléchargés"
  fi
  luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json --base-luaurc=.luaurc --ignore="**/Vendor/**" --ignore="**/_Index/**" src 2>&1 | tail -60
  [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
  # Le plugin est un projet Rojo à part : son sourcemap doit être généré et lu depuis son dossier,
  # sinon les chemins relatifs ne se résolvent pas et tous les require passent pour invalides.
  if [ -d plugin ] && [ -f plugin/assetforge.project.json ]; then
    ( cd plugin \
      && rojo sourcemap assetforge.project.json -o sourcemap.json >/dev/null \
      && luau-lsp analyze --definitions="$DEFS" --sourcemap=sourcemap.json --base-luaurc=.luaurc AssetForge 2>&1 | tail -30 ) || fail=1
  fi
else echo "luau-lsp absent"; fail=1; fi

step "4/5 tests Lune"
if command -v lune >/dev/null; then
  lune run tests/run.luau || fail=1
else echo "lune absent"; fail=1; fi

step "5/5 rojo build"
mkdir -p build
if rojo build default.project.json -o build/AmericanDream.rbxl; then
  size=$(stat -c %s build/AmericanDream.rbxl 2>/dev/null || stat -f %z build/AmericanDream.rbxl)
  echo "taille : $size octets"
  if [ "$size" -lt 51200 ]; then echo "build trop petit (< 50 Ko) : projet Rojo vide ?"; fail=1; fi
else fail=1; fi

echo
if [ $fail -eq 0 ]; then printf '\033[1;32mCHECK OK\033[0m\n'; else printf '\033[1;31mCHECK ÉCHOUÉ\033[0m\n'; fi
exit $fail
