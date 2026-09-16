# ORACLE — moteur de détection de tendances

Le pipeline de production se copie en une soirée. Savoir **quoi** produire et **quand**, non.
ORACLE cherche ce qui **accélère**, pas ce qui est gros : un jeu à 200 000 joueurs, c'est trop
tard ; un jeu à 4 000 qui a triplé en 72 heures, c'est une fenêtre de 10 à 25 jours.

Python **stdlib uniquement**, aucune dépendance, aucune clé obligatoire.

## Démarrage

```bash
cd oracle
python3 ingest.py --db oracle.db          # ~25 s, environ 220 univers
python3 clones.py --db oracle.db          # saturation réelle, toutes les 6 h
python3 features.py --db oracle.db --top 20
```

Lancer le soir, ne rien regarder avant le lendemain matin : il faut **trois points de mesure**
(45 minutes) pour une vélocité, et **12 heures** pour que l'accélération veuille dire quelque chose.

## Cron

```cron
*/15 * * * *  cd /chemin/oracle && python3 ingest.py   --db oracle.db --quiet >> ingest.log 2>&1
17   */6 * * * cd /chemin/oracle && python3 clones.py   --db oracle.db --quiet >> clones.log 2>&1
23   */6 * * * cd /chemin/oracle && python3 external.py --db oracle.db --quiet >> external.log 2>&1
0    *  * * *  cd /chemin/oracle && python3 features.py --db oracle.db --webhook "$DISCORD_WEBHOOK" >> score.log 2>&1
5    9  * * *  cd /chemin/oracle && python3 predictions.py --db oracle.db auto >> log.log 2>&1
```

Le dernier job est le plus important : il enregistre chaque concept repéré comme **refusé**.
Sans les refus, la régression n'apprend que sur les succès et conclut que tout est bon.

## Les fichiers

| Fichier | Rôle |
|---|---|
| `robloxapi.py` | Accès aux API publiques Roblox : pause entre appels, backoff sur 429, aucune donnée non publique. |
| `concepts.py` | Regroupement des jeux par concept : racinisation, nettoyage des emoji et du marketing, similarité Jaccard. |
| `ingest.py` | Ingestion des quatre classements publics, sur ordinateur et téléphone. Arrondi au quart d'heure. |
| `clones.py` | Saturation réelle par recherche publique : combien de clones, et quelle part le leader tient. |
| `external.py` | Signaux hors plateforme : YouTube, Google Trends, TikTok. Chaque source est optionnelle. |
| `features.py` | Score d'opportunité et classement. |
| `predictions.py` | Journal des décisions et recalibrage des poids. |
| `brief.py` | Brief `.json` pour FORGE, avec un verdict qui tranche. |
| `test_oracle.py` | 31 tests, aucun appel réseau. |

## Le score

```
OpportunityScore = w1*accélération + w2*vélocité + w3*(1 - saturation)
                 + w4*facilité_de_production + w5*signal_externe - w6*âge_de_la_trend
```

Puis amorti par la part d'apparitions **sponsorisées** : une visibilité achetée n'est pas une tendance.

Poids de départ : accélération 0,35 · vélocité 0,20 · non-saturation 0,20 · facilité 0,15 ·
externe 0,10 · pénalité d'âge 0,15. **Ce sont des hypothèses.** `predictions.py fit` les
recalibre sur tes propres résultats après dix décisions jugées.

### Trois garde-fous appris en testant

1. **Plancher à 300 joueurs.** Sans lui, un jeu à 3 joueurs qui passe à 9 affiche +200 % et sort
   premier. C'est le bug du premier test (« medal hub »). Ne pas descendre sous 200 sans mesurer.
2. **Un signal absent vaut 0,5, jamais 0.** Une inconnue n'est pas un mauvais score. La saturation
   non mesurée reste à 0,5 : on n'annonce pas qu'un marché est libre sans l'avoir vérifié.
3. **Fenêtres de 6 h et 12 h.** Au-delà, le signal se dilue dans le cycle jour/nuit.

## Le verdict

`brief.py` ne rend pas un score, il tranche :

| Verdict | Quand |
|---|---|
| **y aller** | accélération réelle, marché encore ouvert, score au-dessus de 0,35 |
| **attendre** | signal présent mais la croissance ralentit, ou trop peu de joueurs pour conclure |
| **passer** | marché saturé, trend de plus de 45 jours, ou visibilité majoritairement achetée |

```bash
python3 brief.py --db oracle.db --top 3 --out ../forge/briefs/
python3 brief.py --db oracle.db --concept egg-steal --prompt   # prompt d'enrichissement
```

## Le journal de prédictions

C'est l'étape qui rend le système impossible à copier.

```bash
python3 predictions.py --db oracle.db log --concept lemon-sell --decision skipped --reason "20 clones, leader à 98 %"
python3 predictions.py --db oracle.db settle --id 3 --peak-ccu 4200 --revenue 15000
python3 predictions.py --db oracle.db fit --apply
```

Le résultat est normalisé en échelle logarithmique : passer de 100 à 1 000 joueurs vaut autant
que de 1 000 à 10 000. C'est une loi de puissance, pas une droite.

## Limites connues

1. **Monétisation non mesurée.** L'endpoint des gamepasses exige une session authentifiée.
   On ne le force pas : le signal reste absent plutôt que deviné.
2. **Regroupement lexical.** Racinisation plus similarité Jaccard. Les embeddings deviendront
   utiles quand la base aura plusieurs mois de volume.
3. **TikTok demande une validation de compte.** Sans jeton, la source se saute. C'est le plus gros
   gain restant : TikTok précède Roblox de 5 à 20 jours.
4. **ORACLE ne voit que le haut des classements** plus ce que la recherche publique renvoie.
   Un concept qui monte hors des classements lui échappe encore.

## Ce qu'on ne fait pas

Aucun scraping de données non publiques, aucune tentative de contourner une authentification,
pause systématique entre les appels. Un bannissement d'IP casserait tout le système pour un
gain nul.
