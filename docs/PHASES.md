# Les phases : prompts à coller dans Claude Code, sur ton PC

Une phase par session. Jamais le jeu entier en un message.

Ces prompts supposent que Claude Code est connecté au MCP de Roblox Studio et que Studio est
ouvert sur le place du jeu. Voir `docs/RUNBOOK-MCP.md` pour le montage.

**Avant chaque session :** ouvrir le dépôt, lire `PROGRESS.md`, puis coller le prompt de la phase.
**Après chaque session :** `bash tools/check.sh`, mettre à jour `PROGRESS.md`, commiter.

---

## Phase 0 — Vérifier que le socle tourne (30 min)

> Ouvre le dépôt. Lis `CLAUDE.md` et `PROGRESS.md`.
>
> Construis le place et ouvre-le dans Studio :
> ```
> cd games/american-dream
> rojo build default.project.json -o build/AmericanDream.rbxl
> ```
>
> Puis, en session MCP avec Studio ouvert sur ce fichier :
> 1. Lance un playtest avec `start_stop_play`.
> 2. Lis `get_console_output`. Je veux zéro erreur. Rapporte-moi chaque ligne rouge ou orange.
> 3. Prends une capture avec `screen_capture` et décris ce que tu vois : la ville est-elle
>    construite, le plot est-il attribué, le HUD s'affiche-t-il ?
> 4. Vérifie que l'argent monte tout seul : marche jusqu'au collecteur et collecte.
>
> Ne corrige rien avant de m'avoir montré la liste des problèmes. Corrige ensuite un problème
> à la fois, en relançant `tools/check.sh` puis un playtest après chacun.

**Ce qui est déjà fait et ne demande aucun code :** ville procédurale, six plots, boucle
dropper-tapis-collecteur, achats par boutons physiques, jauge de Vie, Renaissance, marché,
employés, classement, journaux, OPA, monétisation, télémétrie.

**Ce qui va probablement casser au premier playtest :** un `WaitForChild` trop court, une
position de plot qui chevauche une route, une part non ancrée. C'est le but de cette phase.

---

## Phase 1 — Le game feel (2 sessions)

C'est **la** phase qui ne peut pas être automatisée, et celle qui décide si le jeu est bon.

> Session MCP avec Studio ouvert. Joue vraiment : marche, collecte, achète, monte d'acte.
>
> Pour chacun de ces points, dis-moi si c'est satisfaisant, puis corrige :
> 1. **La collecte.** Le retour est-il immédiat ? Le son, le nombre qui monte, la fente qui
>    s'éclaire arrivent-ils dans les 100 ms ?
> 2. **L'achat.** Le bouton pulse-t-il assez pour qu'on le remarque sans qu'il agace ?
>    La machine apparaît-elle avec un effet, ou surgit-elle brutalement ?
> 3. **Le trajet.** La distance dropper-collecteur donne-t-elle envie de marcher, ou est-ce
>    une corvée ? Teste les cinq variantes : `PlotLayout.build(1)` à `(5)`.
> 4. **Le changement d'acte.** La transition d'éclairage se voit-elle ? Est-elle assez lente
>    pour qu'on la sente, assez rapide pour ne pas gêner ?
> 5. **Le burnout.** Le silence coupé net fonctionne-t-il ? C'est le moment le plus fort du jeu.
>
> Règle : une correction, un playtest. Ne change jamais trois choses avant de tester.

---

## Phase 2 — Les assets (1 session + le temps de génération)

> 1. Dans Studio : **Game Settings → Security → Allow Mesh & Image APIs**. Sans ça, les textures
>    sont supprimées sans message d'erreur.
> 2. Construis et installe le plugin :
>    ```
>    cd games/american-dream
>    rojo build plugin/assetforge.project.json -o ~/Documents/Roblox/Plugins/AssetForge.rbxm
>    ```
>    Redémarre Studio.
> 3. Onglet Plugins → **Générer**. Le lot tourne à 5 assets par minute : environ 20 minutes
>    pour les 92 props. Il reprend tout seul après un plantage.
> 4. **Contrôler** : lis le tableau et dis-moi ce qui est à refaire.
> 5. **Exporter**, puis copie la valeur de `ServerStorage.AssetForgeResults` dans
>    `forge/assetforge/results.json` et lance `python3 forge/assetforge/import_results.py`.
> 6. Relance un playtest : les meshes remplacent les greybox tout seuls.
>
> Ensuite, montre-moi les assets générés dix par dix et dis-moi lesquels sont ratés. Compte
> environ 30 % de déchet : c'est normal, on régénère avec un prompt modifié.

Les **13 assets héros** ne passent pas par le lot : ils demandent un modèle détaillé importé en
GLB. La liste sort avec `python3 forge/assetforge/build_manifest.py`.

---

## Phase 3 — Publier et mesurer (1 session + 3 semaines d'attente)

> 1. Crée l'univers sur create.roblox.com, publie le place, passe-le en public.
> 2. Crée les gamepasses et developer products, reporte leurs identifiants dans
>    `src/shared/Config/Monetization.luau`. Un identifiant à 0 désactive l'offre proprement.
> 3. Crée la clé Open Cloud, ajoute `ROBLOX_API_KEY`, `UNIVERSE_ID` et `PLACE_ID` dans les
>    secrets GitHub. Le workflow `deploy.yml` prend le relais.
> 4. Fais dix thumbnails différentes, teste-les. C'est l'asset le plus rentable du projet.
>
> Puis attends. Regarde le Creator Dashboard à J+7 :
> - **rétention à J+1 sous 10 %** : le jeu ne décollera pas, ne mets pas un Robux en publicité ;
> - **session médiane sous 4 minutes** : c'est le design qu'il faut reprendre, pas le code.
>
> À J+21, lance `python3 ledger/tune.py --db ledger.db --days 14` et applique la proposition
> si les tests passent.

---

## Phase 4 — L'usine (après le premier jeu publié, pas avant)

Le piège est de construire l'usine avant d'avoir fabriqué un seul produit.

> 1. Lance ORACLE en lecture seule pendant quatre semaines :
>    ```
>    cd oracle && python3 ingest.py --db oracle.db
>    ```
>    Mets-le en cron (voir `oracle/README.md`). Chaque matin, regarde le classement et note
>    dans le journal ce que tu aurais fait :
>    ```
>    python3 predictions.py --db oracle.db log --concept X --decision skipped --reason "..."
>    ```
>    Les refus comptent autant que les essais. C'est la moitié du signal.
> 2. Après dix décisions jugées :
>    ```
>    python3 predictions.py --db oracle.db fit --apply
>    ```
>    Les poids ne sont plus des hypothèses, ce sont tes résultats.
> 3. Alors seulement, produis un jeu depuis un brief :
>    ```
>    python3 brief.py --db oracle.db --top 1 --out ../forge/briefs/
>    python3 ../forge/generator/new_game.py --brief ../forge/briefs/<slug>.brief.json
>    ```

---

## Le prompt de départ pour un jeu généré

À coller après `new_game.py`, dans une session MCP :

> Lis `games/<slug>/README.md` et `games/<slug>/brief.json`.
>
> **Avant d'écrire une ligne de code**, propose-moi l'architecture : quels modules, quelles
> responsabilités, quels remotes. Attends ma validation. Corriger un plan coûte deux minutes,
> corriger 2 000 lignes coûte une soirée.
>
> Puis construis système par système, dans cet ordre, en testant après chacun :
> 1. la boucle centrale, jouable en 30 minutes de travail ;
> 2. les paliers et les achats ;
> 3. la sauvegarde ;
> 4. l'interface ;
> 5. la monétisation.
>
> Contraintes de `CLAUDE.md`, sans exception : aucune API Roblox de mémoire (vérifie avec
> `tools/rbxdoc.sh`), serveur autoritatif, `--!strict`, tous les textes dans `Strings.luau`,
> mobile d'abord, aucun mécanisme figurant dans les interdits du brief.
>
> Exige un playtest dès que tu enchaînes trois fonctionnalités sans test.
