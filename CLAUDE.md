# CLAUDE.md : règles pour tout agent qui travaille dans ce dépôt

Ce dépôt est une usine à jeux Roblox pilotée par IA. Trois systèmes et un premier jeu :

| Dossier | Rôle |
|---|---|
| `games/american-dream/` | Le tycoon satirique "American Dream" (Rojo, Luau strict, tests Lune). Premier produit, construit à la main avant l'usine. |
| `forge/` | FORGE : production. Générateur de jeu depuis un brief, AssetForge (manifest + plugin Cube 3D + upload Open Cloud), déploiement Open Cloud, kit partagé Luau. |
| `oracle/` | ORACLE : détection de tendances (ingestion API Roblox, scoring V/A/S, journal de prédictions, générateur de brief). Python stdlib uniquement. |
| `ledger/` | LEDGER : télémétrie, analyse de rétention, réglage automatique de l'économie. |
| `docs/` | Spec maître, pipeline d'assets, architecture, runbook MCP, prompts par phase, compte rendu. |
| `tools/` | Scripts de vérification (`check.sh`), consultation de la doc Roblox (`rbxdoc.sh`). |

Lis `PROGRESS.md` avant de commencer une session et mets-le à jour avant de finir.

## Règles non négociables

1. **Aucune API Roblox de mémoire.** Toute classe, méthode ou propriété non vérifiée dans la session est vérifiée dans la doc officielle avant d'être utilisée :
   `tools/rbxdoc.sh <NomDeClasse>` (lit `Roblox/creator-docs` sur GitHub) ou `http_get` sur `https://create.roblox.com/docs/reference/engine/classes/<Classe>`. En session MCP, `execute_luau` après chaque bloc pour prouver que ça tourne.
2. **Serveur autoritatif.** Tout calcul d'argent, de Vie, d'achat ou de progression vit dans `ServerScriptService`. Le client affiche et envoie des intentions. Un RemoteEvent non validé par `RemoteGuard` est un bug.
3. **`--!strict` partout**, `task.wait()` / `task.spawn()` / `task.defer()` uniquement (jamais `wait()`, `spawn()`, `delay()`), un ModuleScript par système, aucun script au-dessus de 600 lignes.
4. **Rien ne passe sans `tools/check.sh`** : selene (lint), luau-lsp (typecheck strict avec les types Roblox), tests Lune, `rojo build` avec vérification de taille. Une erreur console en playtest bloque la suite.
5. **Tests d'abord sur l'économie.** Toute modification de `Config/Economy.luau` doit garder `tests/economy.spec.luau` et la simulation `tests/sim.spec.luau` verts (temps par tier dans la fourchette cible).
6. **Mobile d'abord.** 40 % des joueurs sont sur téléphone : UI tactile, `ScreenInsets = CoreUISafeInsets`, 60 FPS visés, parts décoratives `CanCollide = false` et `CanQuery = false`, StreamingEnabled.
7. **Textes dans `Strings.luau` (FR + EN)**, jamais en dur dans le code. Le test `strings.spec.luau` vérifie que chaque clé existe dans les deux langues.
8. **Monétisation par la valeur.** Interdits : faux compte à rebours, fausse rareté, monnaie intermédiaire qui brouille le prix, payer pour ne pas perdre sa progression, loot box, bouton d'achat placé pour le clic accidentel. `PolicyService` consulté avant tout contenu soumis à politique. Le public est majoritairement mineur : c'est un risque de compte, pas un débat.
9. **Jamais contourner** la modération Roblox, la vérification d'identité, ni scraper des données non publiques. Respecter les rate limits (ORACLE : pause entre appels, backoff sur 429).
10. **Une phase par session.** Faire valider l'architecture avant de coder une phase (`docs/PHASES.md`). Corriger un plan coûte 2 minutes, corriger 2 000 lignes coûte une soirée.

## Boucle de travail en session MCP (Studio ouvert)

1. Lire `PROGRESS.md` et la phase en cours dans `docs/PHASES.md`.
2. `rojo serve games/american-dream` puis connecter le plugin Rojo dans Studio (ou `rojo build -o build/AmericanDream.rbxl` et ouvrir le fichier).
3. Écrire ou modifier un module → `tools/check.sh` → `start_stop_play` → `get_console_output` → `screen_capture` → corriger jusqu'à zéro erreur.
4. Un commit par système qui marche. Message de commit en français, impératif, court.
5. Mettre à jour `PROGRESS.md` : fait / cassé / reste.

## Conventions de code Luau

- Fichiers `.luau`. Modules en PascalCase, variables en camelCase, constantes en UPPER_SNAKE.
- Services serveur dans `src/server/Services/<Nom>Service.luau` exposant `Init()` puis `Start()`. Contrôleurs client dans `src/client/Controllers/<Nom>Controller.luau`, même contrat.
- Logique pure (maths d'économie, génération de monde, règles) dans `src/shared/` sans aucun appel `game:GetService` : c'est ce qui est testé dans Lune.
- Remotes déclarés une seule fois dans `src/shared/Remotes.luau`. Le serveur enveloppe chaque handler avec `RemoteGuard.wrap` (types, rate limit, sanity).
- Assets référencés par identifiant de manifest (`MSH_A1_DROP_LemonadeStand`) via `AssetRegistry`, jamais par `rbxassetid://` en dur dans le gameplay. Un asset absent tombe sur un greybox (part colorée), le jeu reste jouable.

## Ce que l'agent ne fait pas seul

- Créer l'univers, activer les gamepasses / developer products, cocher `EditableImage` / `EditableMesh` dans Game Settings → Security, publier la première fois. Environ 20 minutes à la main, listées dans `docs/MANUEL-RESTANT.md`.
- Juger si c'est fun. Les métriques (`ledger/`) et le playtest du propriétaire tranchent.
- Choisir les slogans finaux (`Config/Lore.luau`) : c'est là que vit le propos du jeu.
