# Notes du refactor

## Vérifications automatiques

- Le build complet Debug réussit avec `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`.
- La suite complète réussit : 74 tests exécutés, 74 réussis, aucun échec ni test ignoré.
- `UserDefaults.standard` est limité à `UserDefaultsSettingsStore`, point d'adaptation prévu.
- Les singletons système (`NSApplication`, `NSWorkspace`, `URLSession`) et ceux imposés par les
  bibliothèques (`LLMModelFactory`) ne sont pas concernés par l'interdiction métier.
- Chaque `@unchecked Sendable` possède désormais un commentaire local décrivant son invariant de
  synchronisation. Leur conversion en acteurs n'est pas mécanique : plusieurs callbacks temps réel
  (`AVAudioEngine`, event tap et watchdogs) doivent rester synchrones.
- `Localizable.xcstrings` utilise le français comme langue source. Les littéraux SwiftUI peuvent être
  extraits automatiquement ; la migration des erreurs techniques construites dans les services reste
  progressive afin de ne pas changer les contrats ni les diagnostics.
- Le contrôle préalable `pgrep xcodebuild` n'est pas disponible dans le bac à sable (`sysmond service
  not found`). Aucun build lancé par cette tâche ne tournait encore lors des validations séquentielles.

## Écarts conservés

Les fichiers suivants dépassent 250 lignes. Ils ont été conservés pendant ce lot pour éviter une
refonte simultanée de code temps réel ou de tests sensibles :

| Fichier | Justification |
| --- | --- |
| `Services/Audio/AudioRecorder.swift` | Chaîne AVAudioEngine, conversion et reprise de périphérique fortement couplées ; extraction à couvrir par des tests audio dédiés. |
| `Services/Hotkey/HotkeyService.swift` | Event tap synchrone et worker d'urgence ; séparation risquée sans harnais CGEvent. |
| `Services/Transcription/SegmentedTranscriber.swift` | Algorithme incrémental et budgets de segments couverts ensemble par la suite actuelle. |
| `App/AppEnvironment.swift` | Composition déclarative uniquement ; factories réparties par domaine dans des extensions dédiées, sans logique métier. |
| `Coordination/DictationCoordinator.swift` | Orchestration de session ; ses paramètres ont déjà été regroupés et les prochaines extractions viseront la présentation des résultats. |
| `DictaMacTests/TextCleanupTests.swift` | Plusieurs scénarios d'intégration HTTP regroupés autour du même harnais. |
| `DictaMacTests/DictationCoordinatorTests.swift` | Fixtures et doubles locaux gardés avec la suite qu'ils décrivent. |

Les `.shared` métier historiques encore présents sont `PersistentDiagnosticLog`, `ModelLoadingGate`
et `PermissionStateCache`. Ils encapsulent respectivement une écriture sérialisée, l'exclusion mutuelle
de chargements lourds et un bit lu depuis des callbacks synchrones. Leur suppression complète demande
de propager ces dépendances jusque dans les APIs statiques et callbacks système ; elle est reportée pour
éviter une modification de concurrence non couverte dans ce lot. Les occurrences restantes de
`NSApplication.shared`, `NSWorkspace.shared`, `URLSession.shared` et `LLMModelFactory.shared` sont des
singletons système ou de bibliothèque explicitement admis.

## Suite recommandée

1. Injecter `PersistentDiagnosticLog` dans `ProcessMemoryDiagnostics` et `AudioRecorder`.
2. Injecter une instance de `ModelLoadingGate` dans les trois consommateurs de modèles.
3. Remplacer `PermissionStateCache.shared` par une dépendance synchrone injectée dans l'injecteur.
4. Extraire les workers audio et event tap derrière des harnais testables avant de scinder leurs fichiers.
