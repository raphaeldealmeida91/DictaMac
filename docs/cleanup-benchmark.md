# Benchmark des modèles MLX de nettoyage

Le runner est prêt, mais le benchmark lourd n’a pas été exécuté. Il utilise 30 cas français et n’effectue aucun téléchargement. Le chargement et le préchauffage sont exclus des latences ; les sorties rejetées restent incluses dans la distance d’édition normalisée.

| Modèle | Cas | Latence médiane | Latence p95 | Rejets validateur | Distance d’édition normalisée | État |
|---|---:|---:|---:|---:|---:|---|
| mlx-community/Qwen2.5-1.5B-Instruct-4bit | 0 | — | — | — | — | Non exécuté |
| mlx-community/Qwen2.5-3B-Instruct-4bit | 0 | — | — | — | — | Non exécuté |
| mlx-community/Qwen2.5-7B-Instruct-4bit | 0 | — | — | — | — | Non exécuté |

Après exécution explicite du test d’intégration Debug, ce fichier est remplacé par les mesures. Un modèle absent de `~/Library/Application Support/DictaMac/Models/Cleanup` apparaît comme ignoré, sans appel réseau.
