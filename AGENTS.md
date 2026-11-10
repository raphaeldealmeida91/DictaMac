## Contexte du projet

DictaMac est une application macOS de barre de menus (`LSUIElement`) dédiée à la dictée vocale :
l'utilisateur maintient la touche `fn`, parle, puis la relâche ; l'audio est transcrit localement avec
WhisperKit et le texte obtenu est collé dans l'application qui était au premier plan.

Contraintes du projet :
- Swift 5.9 ou plus récent, SwiftUI et AppKit, macOS 14 ou plus récent, Apple Silicon.
- L'application reste sans icône dans le Dock et s'utilise depuis la barre de menus.
- Les services substituables sont exposés derrière des protocoles afin de rester testables.
- Utiliser `os.Logger`/`OSLog` pour les journaux ; ne jamais journaliser le texte dicté ni les secrets.
- Aucun force-unwrap dans le code de production.
- La compilation doit rester sans warning (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`).

## Architecture actuelle

- `DictationCoordinator` orchestre le raccourci, l'enregistrement, la transcription, le nettoyage et
  l'injection ; `DictationSessionPolicy` protège les transitions d'état et les générations de session.
- `HotkeyService` observe l'appui/relâchement de `fn` seul via un event tap et filtre les appuis courts.
- `AudioRecorder` capture le microphone et convertit l'audio en mono Float32 à 16 kHz.
- `TranscriptionService`, `WhisperKitTranscriptionService` et `SegmentedTranscriber` assurent le
  chargement des modèles WhisperKit et la transcription locale incrémentale.
- `TextCleanupService` sélectionne `FastRulesTextCleanupService`, `LocalTextCleanupService` (MLX) ou
  `CloudTextCleanupService` (API OpenAI) ; `LocalCleanupModelManager` télécharge et gère le modèle MLX.
- `TextInjector`, `ClipboardTextInjector` et `GeneralPasteboardProvider` collent le résultat puis
  restaurent le presse-papiers, ou laissent le texte copié si le collage n'est pas possible.
- `PermissionsManager` suit les autorisations Microphone, Surveillance de l'entrée et Accessibilité.
- `TranscriptionHistoryStore` conserve localement jusqu'à 20 dictées ; `LaunchAtLoginService` gère le
  lancement à l'ouverture de session.
- `DictationOverlayController` affiche l'état de la dictée ; `DictationDiagnostics`,
  `PersistentDiagnosticLog`, les watchdogs et `WhisperBenchmarkRunner` couvrent diagnostics et mesures.

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

## Conventions de code

- Un type principal par fichier.
- Injecter les dépendances par protocole ; ne pas utiliser `.shared` dans les types métier.
- Utiliser des constantes nommées plutôt que des nombres magiques.
- Limiter les fonctions à moins de 30 lignes.
- Choisir des noms qui expriment l'intention.
- Réserver les commentaires à l'explication du « pourquoi ».
