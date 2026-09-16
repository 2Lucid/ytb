# Montage Claude Code × Roblox Studio (MCP)

Environ deux heures la première fois. Étapes tirées de la documentation officielle
(create.roblox.com/docs/studio/mcp).

## Phase 1 — Installer (20 min)

1. **Roblox Studio à jour.** Le menu MCP n'existe pas sur les anciennes versions.
2. **Node.js 18 ou plus**, puis :
   ```bash
   npm install -g @anthropic-ai/claude-code
   claude    # première exécution : connexion au compte
   ```
3. Cloner le dépôt et s'y placer :
   ```bash
   git clone https://github.com/2Lucid/ytb && cd ytb
   ```
4. Installer les outils Luau :
   ```bash
   # rokit : https://github.com/rojo-rbx/rokit
   cd games/american-dream && rokit install
   ```

## Phase 2 — Ouvrir le canal (10 min)

1. Studio → **Assistant** → menu `…` → **Manage MCP Servers** → activer
   **Enable Studio as MCP server**.
2. **Quick connect** → activer Claude Code. S'il n'apparaît pas : fermer et rouvrir Studio.
3. Plan B, configuration manuelle dans `~/.claude/mcp.json` :

   **macOS**
   ```json
   {"mcpServers":{"Roblox_Studio":{"command":"/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP"}}}
   ```
   **Windows**
   ```json
   {"mcpServers":{"Roblox_Studio":{"command":"cmd.exe","args":["/c","%LOCALAPPDATA%\\Roblox\\mcp.bat"]}}}
   ```
4. Vérifier le voyant vert dans Manage MCP Servers, puis taper `/mcp` dans Claude Code :
   les outils Roblox doivent apparaître.

## Phase 3 — Cadrer l'agent

`CLAUDE.md` est déjà écrit à la racine du dépôt. C'est l'étape que tout le monde saute, et c'est
celle qui évite les APIs inventées. Ne pas la supprimer.

Les outils MCP à réclamer par leur nom :

| Outil | Ce qu'il fait |
|---|---|
| `execute_luau` | Exécute du Luau et renvoie le résultat ou l'erreur. **C'est ce qui prouve qu'une API existe.** |
| `start_stop_play` + `get_console_output` | Playtest et lecture des logs |
| `screen_capture` | L'agent voit ce qu'il a construit |
| `user_keyboard_input` / `user_mouse_input` | Simule un joueur |
| `generate_mesh` / `generate_procedural_model` | Objets 3D depuis un prompt |
| `search_asset` + `insert_asset` | Modèles existants du Creator Store |
| `subagent` | Sous-agent pour les tâches longues |

## Phase 4 — Développer

```bash
cd games/american-dream
rojo serve default.project.json     # branché sur Studio via le plugin Rojo
```

Boucle de travail : écrire → `tools/check.sh` → `start_stop_play` → `get_console_output` →
`screen_capture` → corriger jusqu'à zéro erreur. Un commit par système qui marche.

## Ce qui va casser

| Symptôme | Solution |
|---|---|
| Aucun outil Roblox dans `/mcp` | Redémarrer Studio puis Claude Code, garder une session Studio ouverte |
| Le JSON ne charge pas | Une virgule manquante suffit. Passer dans un validateur. |
| L'agent invente une API | Le renvoyer vers `tools/rbxdoc.sh <Classe>` puis `execute_luau` |
| Marche en solo, casse à plusieurs | De la logique est passée côté client. Audit : tout calcul d'argent doit être serveur. |
| Il réécrit ce qui marchait | Contexte saturé. Nouvelle session, relire `PROGRESS.md`. |
| Le jeu tourne mais il est mou | C'est le tuning. Voir la phase 1 de `docs/PHASES.md`. |
| Les meshes générés sont gris | **Allow Mesh & Image APIs** n'est pas coché dans Game Settings → Security. |

## Ton rôle pendant la construction

- Exiger un playtest si l'agent enchaîne trois fonctionnalités sans test.
- Jouer toi-même toutes les heures. Personne d'autre ne dira si c'est fun.
- Un commit par système qui marche.
