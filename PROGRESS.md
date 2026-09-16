# PROGRESS.md : journal du projet

Format : date, fait, cassé, reste. Le plus récent en haut.

## 2026-09-16 : reconstruction et livraison de l'usine complète

**Contexte.** Le dépôt distant était vide : rien des conversations d'août n'avait été poussé.
Tout a été reconstruit, étendu, testé et poussé.

### Fait

**Socle.** Monorepo, `CLAUDE.md` strict, `tools/check.sh` (porte de qualité unique :
selene, luau-lsp strict avec les types Roblox, tests Lune, build avec vérification de taille),
`tools/rbxdoc.sh` pour ne jamais écrire une API de mémoire.

**American Dream.** Projet Rojo complet et jouable en greybox : ville procédurale de 777 objets
en cinq quartiers, six plots en cinq variantes de disposition, boucle complète, jauge de Vie et
Renaissance, marché, employés, classement, lore, OPA, monétisation, télémétrie, interface tactile,
animations de machines scriptées, éclairage progressif par acte.

**AssetForge.** Manifest de 196 assets, plugin Studio de génération par lot avec reprise après
plantage, contrôle qualité, réimport des identifiants, uploader Open Cloud.

**ORACLE.** Ingestion des classements publics (testée en live : 224 univers), regroupement par
concept avec racinisation, saturation mesurée par recherche publique (vérifié : le concept des
œufs a 20 clones et un leader à 98 %), scoring V/A/S, journal de prédictions, régression des
poids (retrouve la vérité cachée à 0,02 près, R² de 0,99), générateur de brief qui tranche.

**LEDGER.** Collecteur, agrégation, entonnoir par variante, diagnostic et réglage automatique de
l'économie, validé de bout en bout sur un décrochage simulé de 78 %.

**FORGE.** Générateur de jeu depuis un brief : un squelette qui passe typecheck, lint et tests
dès la première minute.

**CI.** Quatre workflows : qualité, déploiement Open Cloud avec validation manuelle, ORACLE
horaire, LEDGER hebdomadaire en pull request.

### Vérifié

| | |
|---|---|
| Tests Luau | 65, verts |
| Tests Python | 56, verts (31 ORACLE, 16 LEDGER, 9 générateur) |
| Typecheck strict | zéro erreur |
| Lint | zéro avertissement |
| Build | 148 Ko |
| ORACLE en conditions réelles | 224 univers ingérés, saturation mesurée |

### Cassé ou non vérifié

- **Rien n'a tourné dans Roblox Studio.** Le code est vérifié par tout ce qui peut l'être hors
  de Roblox, mais le premier playtest reste à faire. C'est la phase 0.
- Les identifiants d'assets, de gamepasses, de badges et de developer products sont à 0 : les
  offres sont désactivées proprement et les assets tombent sur des greybox.
- ORACLE a besoin de douze heures d'ingestion réelle avant que l'accélération ait un sens.
  Les tests de scoring tournent sur des séries simulées.
- Google Trends et TikTok ne sont pas branchés (clés absentes). Les sources se sautent
  proprement et le signal reste à « inconnu ».

### Reste

1. Phase 0 : premier playtest dans Studio, corriger ce qui casse.
2. Phase 1 : le game feel. Ne s'automatise pas.
3. Phase 2 : générer les assets (cocher *Allow Mesh & Image APIs* d'abord).
4. Phase 3 : publier, mesurer, laisser LEDGER proposer.
5. Phase 4 : ORACLE en lecture seule pendant quatre semaines avant de lui faire confiance.

Détail dans `docs/PHASES.md`. Ce qui reste manuel : `docs/MANUEL-RESTANT.md`.
