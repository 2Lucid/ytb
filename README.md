# Usine à jeux Roblox

Trois systèmes et un premier jeu, construits pour qu'un agent puisse produire un jeu Roblox de
bout en bout et corriger son économie tout seul.

| Dossier | Rôle |
|---|---|
| `games/american-dream/` | **American Dream** : tycoon satirique sur le capitalisme. Le premier produit. |
| `oracle/` | Détection de tendances : quoi produire, et quand. |
| `forge/` | Production : du brief au jeu, et les assets. |
| `ledger/` | Mesure et réglage automatique de l'économie. |
| `docs/` | Phases, montage MCP, architecture, ce qui reste manuel. |
| `tools/` | Porte de qualité et consultation de la doc Roblox. |

## Démarrer

```bash
git clone https://github.com/2Lucid/ytb && cd ytb
cd games/american-dream && rokit install && cd ../..

bash tools/check.sh                    # lint, typecheck, tests, build
cd games/american-dream
rojo build default.project.json -o build/AmericanDream.rbxl
```

Ouvrir le fichier dans Studio et lancer un playtest : la ville se construit, un plot est attribué,
la boucle tourne. Voir `docs/PHASES.md` pour la suite.

## Le jeu

On part d'un carton dans une ruelle, on finit à la tête d'une holding cotée, pendant que le jeu
montre discrètement ce que ça a coûté.

Cinq actes : la Ruelle, le Commerce, l'Usine, la Tour, la Holding. Deux ressources : le `Cash`
qui monte et se voit, et la `Vie` qui descend en silence quand la base grandit. À zéro, c'est le
burnout : tout est vendu, on se réveille dans la ruelle avec un multiplicateur permanent, et les
slogans du début reviennent retournés.

Ce qui tourne déjà : ville procédurale de 777 objets en cinq quartiers, six plots en cinq
variantes de disposition pour l'A/B test, boucle dropper-tapis-collecteur, achats par boutons
physiques, loyers, employés, événements de marché, classement en indice boursier, douze journaux
ramassables, panneaux publicitaires dont les slogans changent avec la fortune, OPA entre joueurs,
monétisation, télémétrie.

## L'état réel

| | |
|---|---|
| Tests | 65 en Luau, 56 en Python |
| Typecheck | strict avec les types Roblox, zéro erreur |
| Lint | zéro avertissement |
| Assets | 196 au manifest, 0 généré (greybox partout, le jeu tourne) |
| Playtest dans Studio | **jamais lancé** — c'est la phase 0 |
| Publié | non |

Le code est vérifié par tout ce qui peut l'être hors de Roblox. Ce qui demande Studio n'a pas
encore été fait : c'est la première chose à faire, et `docs/PHASES.md` donne le prompt.

## Les commandes

```bash
bash tools/check.sh                                   # porte de qualité complète
bash tools/rbxdoc.sh GenerationService GenerateModelAsync   # doc officielle Roblox

cd oracle
python3 ingest.py --db oracle.db                      # ~25 s, environ 220 univers
python3 clones.py --db oracle.db                      # saturation réelle
python3 features.py --db oracle.db --top 20           # classement des fenêtres
python3 brief.py --db oracle.db --top 1 --out ../forge/briefs/

python3 forge/generator/new_game.py --brief forge/briefs/<slug>.brief.json

cd ledger
python3 collector.py rollup --db ledger.db
python3 tune.py --db ledger.db --days 7               # diagnostic et proposition
```

## Prochaines étapes

1. **Phase 0** : premier playtest dans Studio. Rien d'autre n'a de sens avant.
2. **Phase 1** : le game feel. C'est ce qui décide si le jeu est bon, et ça ne s'automatise pas.
3. **Phase 2** : générer les assets, cocher *Allow Mesh & Image APIs* avant.
4. **Phase 3** : publier, mesurer, laisser LEDGER proposer les réglages.
5. **Phase 4** : ORACLE en lecture seule pendant quatre semaines avant de lui faire confiance.

Détail dans `docs/PHASES.md`. Ce qui reste manuel, sans enjoliver : `docs/MANUEL-RESTANT.md`.

## Les règles

`CLAUDE.md` à la racine. Les trois qui comptent le plus :

1. **Aucune API Roblox de mémoire.** On vérifie dans la doc officielle ou on exécute.
2. **Le serveur calcule, le client affiche.**
3. **Monétisation par la valeur.** Pas de loot box, pas de faux compte à rebours, pas de fausse
   rareté. Le public est majoritairement mineur : c'est un risque de compte, pas un débat.
