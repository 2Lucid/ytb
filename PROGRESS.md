# PROGRESS.md : journal du projet

Format : date, fait, cassé, reste. Le plus récent en haut.

## 2026-09-16 : reconstruction du dépôt et continuation

**Contexte.** Le dépôt distant était vide. Les livrables des conversations d'août (spec, pipeline d'assets, architecture, ORACLE) n'avaient jamais été poussés. Tout a été reconstruit ici et poussé, puis étendu.

**Fait.**
- Monorepo : `games/american-dream`, `forge/`, `oracle/`, `ledger/`, `docs/`, `tools/`, CI GitHub Actions.
- `CLAUDE.md` strict (vérification d'API, serveur autoritatif, `--!strict`, tests d'économie, mobile d'abord, monétisation par la valeur).
- Jeu American Dream : projet Rojo complet (voir `games/american-dream/README.md` pour l'état par module).
- ORACLE reconstruit et testé en live contre l'API Roblox (voir `oracle/README.md`).
- AssetForge : manifest des assets, plugin Studio de génération Cube 3D par lot, contrôle qualité, uploader Open Cloud.
- LEDGER : télémétrie in-game, collecteur, job de réglage de l'économie.

**Cassé / non vérifié.**
- Rien n'a encore tourné dans Roblox Studio : le code est linté, typé (luau-lsp strict avec les types Roblox) et testé en Lune, mais le premier playtest est à faire (Phase 1 de `docs/PHASES.md`).
- Les identifiants d'assets, de gamepasses, de badges et de developer products sont à 0 : à remplir après création côté Creator Hub.

**Reste.**
- Voir `docs/MANUEL-RESTANT.md` et la section "Prochaines étapes" du `README.md`.
