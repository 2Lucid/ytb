# FORGE — du brief au jeu publié

FORGE transforme un brief d'ORACLE en jeu Roblox. Le pipeline est celui-ci :

```
brief.json (ORACLE)
    -> generator/new_game.py      squelette Rojo qui compile, se teste et se déploie
    -> code de gameplay           la partie qui demande du jugement
    -> assetforge/                assets 3D, 2D, audio
    -> .github/workflows/ci.yml   lint, typecheck, tests, build
    -> .github/workflows/deploy.yml   publication Open Cloud
    -> LEDGER                     mesures, puis retour au réglage
```

## Générer un jeu

```bash
python3 forge/generator/new_game.py --brief forge/briefs/lemon-sell.brief.json
bash tools/check.sh games/lemon-sell
```

Ce qui est **copié** depuis American Dream : le kit qui a déjà servi — utilitaires, sauvegarde
avec verrouillage de session, garde des remotes, greybox, télémétrie, harnais de test.
C'est le capital de l'usine : il se rentabilise à chaque nouveau jeu.

Ce qui est **généré** depuis le brief : la configuration d'économie dérivée du genre, les chaînes,
les tests de forme, le README avec le verdict d'ORACLE et les interdits de monétisation.

Ce qui **reste à écrire** : la boucle de jeu. C'est là que se joue la différence entre un jeu et
un squelette, et c'est la seule partie qui demande du jugement.

## AssetForge

Voir `assetforge/` et `games/american-dream/plugin/README.md`.

| Étape | Commande |
|---|---|
| Écrire le manifest | `python3 assetforge/build_manifest.py` |
| Générer les meshes | plugin Studio, bouton **Générer** |
| Contrôler la qualité | plugin Studio, bouton **Contrôler** |
| Réimporter les identifiants | `python3 assetforge/import_results.py` |
| Envoyer un fichier externe | `python3 assetforge/upload_open_cloud.py --file x.glb --id MSH_...` |

## La règle qui tient tout

Un asset absent vaut un greybox, jamais une erreur. Le jeu est jouable avant la première
génération, et chaque asset produit remplace silencieusement son greybox. C'est ce qui permet
de coder le gameplay et de produire les assets en parallèle.

## Ce que FORGE ne fait pas

Créer l'univers, activer les gamepasses, cocher les toggles de Game Settings, publier la
première fois, passer la modération. Environ 20 minutes à la main, une seule fois par jeu.
Voir `docs/MANUEL-RESTANT.md`.
