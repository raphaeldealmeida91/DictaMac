## Règles de build (le Mac de l'utilisateur doit rester utilisable)
- Utilise toujours un derivedDataPath persistant : -derivedDataPath ~/Library/Caches/DictaMac-Codex-DD.
  Ne le supprime pas à la fin d'une tâche (les rebuilds complets de MLX Swift sont très lourds).
- Limite la parallélisation : -jobs 4 (ou moins) et lance les commandes lourdes avec
  `taskpolicy -b` pour qu'elles tournent en priorité basse.
- N'exécute pas plusieurs xcodebuild en parallèle. Avant un build, vérifie qu'aucun autre xcodebuild
  ne tourne (pgrep xcodebuild).
- Pour valider, préfère `build-for-testing` puis `test-without-building`, et -only-testing sur les
  suites concernées quand la tâche est locale.
- Ne lance jamais de build complet pendant que l'utilisateur teste l'app (demande-lui).
