# Architecture de l'usine

Trois systèmes, un produit. Le produit vient d'abord : construire l'usine avant d'avoir fabriqué
un seul jeu est le piège classique.

```
                 ORACLE                    FORGE                     LEDGER
            détecter la fenêtre      produire le jeu            mesurer et corriger

   API Roblox ──┐
   recherche  ──┼─> score V/A/S ──> brief.json ──> squelette ──> gameplay ──> assets
   YouTube    ──┤        │                              │                       │
   Trends     ──┘        │                              └──> CI ──> Open Cloud ─┘
                         │                                                      │
                         └──────────── poids recalibrés <── journal <── mesures ┘
```

La boucle se ferme : ce qu'un jeu rapporte réellement recalibre ce qu'ORACLE considère comme
un bon pari.

## ORACLE — savoir quoi produire

Le pipeline de production se copie en une soirée. Savoir quoi produire et quand, non.

Cherche l'**accélération**, pas la taille. Un jeu à 200 000 joueurs, c'est trop tard. Un jeu à
4 000 qui a triplé en 72 heures, c'est une fenêtre de 10 à 25 jours.

Mesure aussi la **saturation**, qui dit quand ne PAS y aller. C'est la moitié de la valeur.

Ce qui le rend impossible à copier : le journal de prédictions. Chaque concept regardé y est
consigné, **y compris ceux qu'on écarte**, puis confronté au résultat à J+30. Après dix
décisions, une régression remplace les poids de départ par ce que tes propres résultats disent.

Détail dans `oracle/README.md`.

## FORGE — produire

Deux moitiés.

**Le générateur** transforme un brief en projet Rojo qui compile, se teste et se déploie dès la
première minute. Il copie le kit qui a déjà servi (utilitaires, sauvegarde avec verrouillage de
session, garde des remotes, greybox, télémétrie, harnais de test) et génère ce qui dépend du
brief. C'est le capital de l'usine : il se rentabilise à chaque nouveau jeu.

**AssetForge** produit les assets : manifest, génération par lot avec Cube 3D, contrôle qualité,
upload Open Cloud, réinjection des identifiants dans le code.

La règle qui tient tout : **un asset absent vaut un greybox, jamais une erreur.** Le jeu est
jouable avant la première génération, et chaque asset remplace silencieusement son greybox.
C'est ce qui permet de coder le gameplay et de produire les assets en parallèle.

Détail dans `forge/README.md`.

## LEDGER — mesurer et corriger

Les chiffres de la spec sont une hypothèse. LEDGER les confronte au réel.

Relie chaque étape de l'entonnoir au paramètre d'économie qui la gouverne. Un décrochage de 78 %
à l'entrée de l'acte 2 pointe vers son coût d'entrée, et propose de le baisser proportionnellement
à la gravité, plafonné à 40 %.

Rien n'est appliqué sans validation, et les tests d'économie tranchent après coup.

Détail dans `ledger/README.md`.

## Les décisions qui structurent tout

**Le serveur calcule, le client affiche.** Aucun montant ne vient du client. Un RemoteEvent non
validé par `RemoteGuard` est un bug, pas un raccourci.

**La logique pure est séparée du moteur.** Tout ce qui est dans `src/shared/Sim/` et
`src/shared/WorldGen/` n'appelle jamais `game:GetService`. C'est ce qui permet de le tester en
Lune, hors Roblox, en une demi-seconde. C'est la raison pour laquelle 65 tests tournent à chaque
commit sans ouvrir Studio.

**Les tests décrivent la forme, pas les chiffres.** Un test qui épingle `unlockCost == 500`
bloque la boucle d'apprentissage pour toujours. Les tests vérifient que le premier palier est
gratuit, que les coûts croissent, que le temps par palier reste dans une fourchette. Les chiffres
peuvent bouger, la progression reste tenue.

**Aucun asset en dur.** Tout passe par un identifiant de manifest et `AssetRegistry`. Un asset
absent tombe sur un greybox.

**La production est déterministe.** Même graine, même ville, sur tous les serveurs et dans les
tests. C'est ce qui permet de tester une ville de 777 objets sans l'instancier.

## Ordre de construction

1. FORGE minimal sur un seul jeu, publié à la main. ✔
2. CI et déploiement Open Cloud. ✔
3. Instrumentation analytics. ✔
4. **ORACLE en lecture seule pendant quatre semaines** : il prédit, tu vérifies.
5. Générateur de brief : la boucle se ferme. ✔ (en attente des données de l'étape 4)
6. Montée en cadence, **pas avant trois jeux sortis à la main**.

Les étapes marquées sont livrées. L'étape 4 demande du temps réel, pas du code.

## Ce que l'usine ne remplace pas

Savoir si c'est fun. L'après-lancement. Le choix des slogans. Voir `docs/MANUEL-RESTANT.md`.
