# Ce qui reste à faire à la main

Compte honnête, sans prétendre qu'une étape est automatisée quand elle ne l'est pas.

La chaîne va jusqu'à **environ 95 %** : manifest, génération d'assets, upload, build, tests,
publication, analytics, réglage de l'économie, redéploiement. Les 5 % restants sont ci-dessous.

## Techniquement impossible à automatiser

Ces étapes n'ont pas d'API. Elles passent par l'interface de Studio ou du Creator Hub.

| Étape | Où | Temps | Fréquence |
|---|---|---|---|
| Créer l'univers et le place | create.roblox.com | 3 min | une fois par jeu |
| **Allow Mesh & Image APIs** | Studio → Game Settings → Security | 30 s | une fois par jeu |
| Activer les requêtes HTTP (si collecteur LEDGER) | Studio → Game Settings → Security | 30 s | une fois par jeu |
| Créer les gamepasses et developer products | Creator Hub → Monetization | 8 min | une fois par jeu |
| Reporter les identifiants dans `Config/Monetization.luau` | éditeur | 2 min | une fois par jeu |
| Créer les badges | Creator Hub → Badges | 3 min | une fois par jeu |
| Première publication et passage en public | Studio → File → Publish | 2 min | une fois par jeu |
| Créer la clé Open Cloud et les secrets GitHub | create.roblox.com + GitHub Settings | 5 min | une fois |

**Total : environ 25 minutes par jeu, une seule fois.**

Oublier « Allow Mesh & Image APIs » est le piège classique : les textures générées sont supprimées
**sans le moindre message d'erreur**. Si le lot sort des meshes gris, c'est ça.

## Jamais contourner

La modération de chaque asset, la vérification d'identité, les paiements. Contourner, c'est le
compte banni, le jeu supprimé et les revenus perdus. Un asset refusé est refusé : on change le
prompt, on ne cherche pas la faille.

Compter **des rejets sans explication** sur une partie des assets générés. C'est normal.

## Automatisable, mais à ne pas automatiser

| Étape | Pourquoi |
|---|---|
| Trier les assets générés | Compter environ 30 % de ratés. Le contrôle qualité voit « valide », pas « moche ». |
| Les trois animations qui portent l'émotion | `Exhausted`, `Collapse`, `WakeUp`. La passe automatique donne un mouvement correct et sans intention. Retouche dans l'Animation Editor. |
| Choisir les slogans définitifs | `Config/Lore.luau`. C'est là que vit le propos du jeu. Les slogans livrés sont une première version. |
| Choisir la thumbnail | L'asset le plus rentable du projet. Le taux de clic est le vrai levier de découverte. En tester dix. |

## Le vrai goulot

Ce qui reste n'est pas technique.

1. **Savoir si c'est fun.** Aucun log ne le dit. Les métriques de LEDGER le disent
   indirectement, avec trois semaines de retard. Un playtest le dit tout de suite.
2. **L'après-lancement.** Thumbnail, retours des joueurs, correctifs, communauté. C'est
   environ 80 % du succès d'un jeu Roblox, et 0 % en est automatisable.
3. **Le level design.** L'IA fait mieux que quelqu'un qui n'en a jamais fait. Le problème n'est
   pas la production, c'est que personne ne dit si c'est bien. Trois façons de s'en sortir
   sans payer : le playtest comme juge (les cinq variantes de disposition sont déjà en A/B
   test), jouer vingt minutes à chacun des dix gros tycoons du moment, et faire jouer
   quelqu'un dix minutes en le regardant sans parler.

## L'expérience à faire si tu veux tester le 100 % automatique

Sortir cinq jeux sans aucune intervention de gameplay, mesurer visites et rétention à J+1 à
trois semaines. C'est la seule façon d'avoir une réponse chiffrée plutôt qu'une opinion.

Mise en garde : Roblox enterre le spam. Cinquante jeux médiocres, c'est cinquante jeux à zéro
visite et un compte potentiellement signalé. Le volume ne marche que si chaque jeu passe la
barre du « correct ».
