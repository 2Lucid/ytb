# American Dream

Tycoon satirique sur le capitalisme, le matérialisme et les grandes villes. On part d'un carton
dans une ruelle, on finit à la tête d'une holding cotée, pendant que le jeu montre discrètement
ce que ça a coûté.

Le jeu ne fait jamais la morale. Les chiffres et le décor le disent.

## La boucle

Dropper → tapis → collecteur → `Cash` → bouton d'achat physique → machine supérieure → acte suivant.

Double ressource, c'est le cœur du concept :

- **`Cash`** : visible, il monte.
- **`Vie`** : une jauge silencieuse en haut à droite qui descend quand la base grandit. Jamais
  expliquée au début.

À `Vie` = 0, c'est le **burnout** : le son se coupe net, tout est vendu, on se réveille dans la
ruelle. Le multiplicateur permanent reste. C'est la **Renaissance**, et l'écran reprend les
slogans du début, retournés.

## Les cinq actes

| Acte | Lieu | Ce qui arrive |
|---|---|---|
| 1 | La Ruelle | Stand de limonade, cageots, tirelire. Tutoriel déguisé. |
| 2 | Le Commerce | Superette, premiers employés, premiers loyers. |
| 3 | L'Usine | Chaîne de production, cadence, fumée qui monte. |
| 4 | La Tour | Open space, actionnaires, la ville se dégrade. |
| 5 | La Holding | Conseil d'administration, OPA sur les autres joueurs. |

L'éclairage suit : brumeux et froid au début, publicité aveuglante à la fin. La transition est
continue, jamais brutale.

## L'état par module

| Module | État |
|---|---|
| Ville procédurale (777 objets, 5 quartiers) | écrit, testé, **jamais vu dans Studio** |
| Plots (6, en 5 variantes A/B) | écrit, testé |
| Économie, production, collecte, loyers | écrit, testé, simulé |
| Vie, burnout, Renaissance | écrit, testé |
| Marché (booms et krachs) | écrit, testé |
| Employés, classement, journaux, OPA | écrit |
| Monétisation, télémétrie | écrit, identifiants à créer |
| Interface (HUD, boutique, journaux, classement) | écrit |
| Animations de machines, éclairage, son | écrit, assets manquants (greybox) |
| Assets | 196 au manifest, **0 généré** |
| Playtest | **jamais lancé** |

Tout ce qui peut être vérifié hors de Roblox l'est : 65 tests, typecheck strict, lint propre.
Ce qui demande Studio ne l'est pas encore. Voir la phase 0 de `docs/PHASES.md`.

## L'équilibrage mesuré

La simulation d'une session parfaite (`tests/sim.spec.luau`) donne :

| Repère | Temps |
|---|---|
| Acte 2 | 3,8 min |
| Acte 3 | 9,5 min |
| Acte 4 | 25 min |
| Acte 5 | 58 min |
| Premier burnout | 66 min |

Ce sont des hypothèses. LEDGER les corrigera sur la rétention réelle.

## Commandes

```bash
rokit install
bash ../../tools/check.sh                              # lint, typecheck, tests, build
rojo build default.project.json -o build/AmericanDream.rbxl
rojo serve default.project.json                         # branché sur Studio
lune run tests/run.luau                                 # tests seuls, une demi-seconde
rojo build plugin/assetforge.project.json -o ~/Documents/Roblox/Plugins/AssetForge.rbxm
```

## Structure

```
src/shared/     logique pure, testable hors Roblox (aucun game:GetService)
  Config/       économie, lore, monétisation, machines, monde, dispositions
  Sim/          maths d'économie, Vie, marché, OPA, sauvegarde, bot d'équilibrage
  WorldGen/     génération de la ville et des plots, palette
  Util/         signal, générateur aléatoire déterministe, formatage, limiteur
src/server/     services autoritatifs, constructeurs d'instances
src/client/     contrôleurs et interface
plugin/         AssetForge, génération d'assets par lot
tests/          8 fichiers, 65 tests
```

## Les règles qui ne bougent pas

Voir `CLAUDE.md` à la racine. Pour ce jeu en particulier :

- Aucun calcul d'argent côté client. La production est virtuelle côté serveur ; les objets qui
  tombent sur le tapis sont purement décoratifs et locaux.
- Tous les textes dans `Strings.luau`, FR et EN.
- Un asset absent vaut un greybox. Le jeu reste jouable.
- Les slogans de `Config/Lore.luau` sont une première version. C'est là que vit le propos du
  jeu : c'est à toi de les trancher.
