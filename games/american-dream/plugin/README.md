# Plugin AssetForge

Génère en lot les meshes du manifest avec Cube 3D (`GenerationService`), les publie en assets
persistants (`AssetService:CreateAssetAsync`) et écrit un rapport que le dépôt réinjecte.

## Installation

```bash
rojo build plugin/assetforge.project.json -o ~/Documents/Roblox/Plugins/AssetForge.rbxm
```

Redémarrer Studio : l'onglet **Plugins** montre quatre boutons (Générer, Contrôler, Exporter, Réinitialiser).

## Avant le premier lot (à faire à la main, une fois)

1. **Game Settings → Security → Allow Mesh & Image APIs** : sans ça, les textures sont supprimées
   sans le moindre message d'erreur.
2. Ouvrir le place du jeu construit par Rojo : le manifest arrive dans
   `ReplicatedStorage.AssetForgeManifest`.

## Utilisation

| Bouton | Ce qu'il fait |
|---|---|
| Générer | Produit tous les meshes encore en attente, 5 par minute, en sautant les assets héros. Reprend après un plantage. Cliquer une seconde fois demande l'arrêt propre. |
| Contrôler | Tableau des problèmes : jamais généré, échec, sans texture, hors budget de triangles. |
| Exporter | Écrit le rapport JSON dans `ServerStorage.AssetForgeResults` et le sélectionne. |
| Réinitialiser | Oublie la progression locale. Ne supprime aucun asset déjà publié. |

## Après le lot

Copier la valeur de `ServerStorage.AssetForgeResults` dans `forge/assetforge/results.json`, puis :

```bash
python3 forge/assetforge/import_results.py
```

Le script met à jour `assets/manifest.json` et régénère `src/shared/Generated/AssetIds.luau`.
Chaque identifiant absent reste à 0 : le jeu affiche un greybox et reste jouable.

## Les 13 assets héros

Vus de près, ils ne passent pas par le lot : ils viennent d'un modèle détaillé importé en GLB
(géométrie et matériaux dans un seul fichier, meilleur format pour l'importateur Roblox).
La liste est affichée par `python3 forge/assetforge/build_manifest.py`.
