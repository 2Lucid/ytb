# LEDGER — télémétrie, rétention et réglage de l'économie

Les chiffres de la spec sont une hypothèse. LEDGER la confronte au réel et propose un ajustement
chiffré. Il n'applique jamais rien tout seul : il ouvre une proposition, un humain valide, et les
tests d'économie du jeu décident si le réglage tient.

Python **stdlib uniquement**.

## Ce que Roblox ne donne pas

`AnalyticsService` alimente déjà les tableaux de bord officiels (entonnoirs, progression, économie).
LEDGER sert à ce qu'ils ne montrent pas :

- l'entonnoir **par variante de disposition** du plot, pour trancher l'A/B test ;
- le **palier exact** où le joueur décroche, relié au paramètre d'économie responsable ;
- le **réglage automatique** de ce paramètre, testé avant d'être proposé.

## Démarrage

```bash
cd ledger
python3 collector.py serve --db ledger.db --port 8787     # reçoit les lots du jeu
python3 collector.py rollup --db ledger.db                # agrège (toutes les heures)
python3 collector.py report --db ledger.db --days 7
python3 tune.py --db ledger.db --days 7                   # diagnostic et proposition
python3 tune.py --db ledger.db --apply --proposal 1
bash ../tools/check.sh                                     # les tests valident ou refusent
```

Côté jeu, renseigner `COLLECTOR_URL` dans `games/american-dream/src/shared/Config/Telemetry.luau`
et autoriser les requêtes HTTP dans Game Settings. Laissé vide, le jeu n'envoie rien et se contente
d'`AnalyticsService` : aucune erreur, aucune dépendance.

## Cron

```cron
7  * * * *  cd /chemin/ledger && python3 collector.py rollup --db ledger.db >> rollup.log 2>&1
0  9 * * 1  cd /chemin/ledger && python3 tune.py --db ledger.db --days 7 >> tune.log 2>&1
```

Le réglage tourne une fois par semaine, pas tous les jours : réagir au bruit quotidien abîme
l'économie plus qu'il ne l'améliore.

## Les trois chiffres qui décident

| Métrique | Plancher | Ce que ça veut dire en dessous |
|---|---|---|
| Rétention à J+1 | **10 %** | Le jeu ne décollera pas. Ne pas mettre un Robux en publicité. |
| Session médiane | **4 min** | C'est le design qu'il faut reprendre, pas le code. |
| Décrochage sur une étape | **35 %** | Un palier coûte trop cher ou arrive trop tôt. |

## Comment un décrochage devient un réglage

Chaque étape de l'entonnoir est reliée au paramètre d'économie qui la gouverne. Un décrochage à
« act_2 » pointe vers `Economy.Tiers[2].unlockCost`. La correction est proportionnelle à la gravité
du décrochage, **plafonnée à 40 %** : on ne divise jamais un coût par plus que ça d'un coup.

Exemple mesuré sur des données simulées :

```
   5. first_upgrader          200 joueurs  100.0%
   6. act_2                    45 joueurs   22.5%  (-78%)  <- décrochage

DIAGNOSTIC : décrochage de 78% à « act_2 » : l'entrée dans l'acte 2 est un mur
  Economy.Tiers[2].unlockCost    500.0 -> 350
```

## Garde-fous

1. **Sous 50 joueurs sur la fenêtre, on ne touche à rien.** En dessous, le bruit domine.
2. **Jamais plus de 40 % de baisse d'un coup**, et la cadence ne descend jamais sous 0,5 s.
3. **Rien n'est appliqué sans validation**, et `tools/check.sh` doit rester vert après application.
4. **Une variante A/B ne gagne qu'au-delà de 15 % d'écart** sur 20 joueurs minimum par variante.
   En dessous, c'est du bruit.

## Une leçon apprise en construisant

Les tests d'économie épinglaient les chiffres exacts de la spec (`unlockCost == 500`). Un tel test
bloque la boucle d'apprentissage pour toujours : tout réglage automatique le casse. Ils testent
maintenant la **forme** de la progression — premier acte gratuit, coûts strictement croissants,
acte 5 au moins mille fois l'acte 2, temps par palier dans une fourchette — et laissent les chiffres
bouger. C'est ce qui rend l'automatisation sûre.

## Les fichiers

| Fichier | Rôle |
|---|---|
| `schema.sql` | Événements bruts, jours-joueurs, entonnoir, métriques quotidiennes, propositions. |
| `collector.py` | Serveur HTTP d'ingestion, agrégation, rapport lisible. |
| `tune.py` | Diagnostic, proposition chiffrée, application dans `Config/Economy.luau`. |
| `test_ledger.py` | 16 tests, dont la réécriture réelle de la configuration. |
