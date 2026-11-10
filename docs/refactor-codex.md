# Refonte DictaMac — plan de prompts pour Codex

Ordre d'exécution : 0 → 7. Un prompt = une branche de travail = un commit. Ne passe au suivant que si
le build et les tests du précédent sont verts. Chaque prompt est autonome : copie la section entière
(du titre jusqu'au prochain `---`) dans Codex.

Constats de départ (code actuel, ~6 000 lignes Swift) :
- `DictationCoordinator` (460 l.) cumule : orchestration, boucle d'alimentation audio, minuteurs, trois
  étapes de pipeline avec logs/signposts/watchdog copiés-collés, historique, métriques, sons, handlers d'urgence.
  Il dépend de classes concrètes (`HotkeyService`, `AudioRecorder`, `DictationOverlayController`) et de ~32 `.shared`.
- Les préférences sont dispersées dans 6 enums (`TextCleanupPreferences`, `TranscriptionPreferences`,
  `HistoryPreferences`, `FeedbackSoundPreferences`, `RecordingDurationPreferences`, `EmergencyHotkeyPreferences`)
  qui lisent `UserDefaults.standard` en dur (23 occurrences).
- Fichiers fourre-tout : `TextCleanupService.swift` (7 types), `LocalTextCleanupService.swift`,
  `DictationDiagnostics.swift`, `EmergencyWatchdog.swift`, `TranscriptionService.swift`.
- `ConfiguredTextCleanupService` utilise un `switch` sur le moteur (fermé à l'extension).
- `AppDelegate` mélange cycle de vie, pression mémoire, mode sûr, heartbeat et `NSAlert`.
- `SettingsView` (501 l.) : ~25 `@AppStorage`, toutes les sections dans un seul type, un `ScrollView` à la suite.
- Le projet Xcode n'utilise PAS de groupes synchronisés : tout nouveau fichier doit être ajouté au
  `project.pbxproj` (cible `DictaMac`, ou cible de tests pour les tests).

---

## Bloc à coller au début de CHAQUE prompt (contraintes communes)

```
Contraintes absolues :
- Respecte AGENTS.md (règles de build incluses : derivedDataPath persistant, -jobs 4, taskpolicy -b,
  jamais deux xcodebuild en parallèle, build-for-testing puis test-without-building, demande-moi avant un build complet).
- Refactoring pur : AUCUN changement de comportement visible, sauf pour les prompts 5 à 7 (design).
- Swift 5.9, strict concurrency = complete, SWIFT_TREAT_WARNINGS_AS_ERRORS = YES : zéro warning.
- Aucun force-unwrap en code de production. Ne jamais journaliser le texte dicté ni les secrets.
- Les fichiers ajoutés/déplacés/supprimés doivent être reflétés dans DictaMac.xcodeproj (project.pbxproj),
  cibles correctes (app vs DictaMacTests). Vérifie qu'aucun fichier n'est orphelin ou référencé en double.
- Tous les tests existants restent verts. Ajoute des tests pour tout nouveau comportement isolé.
- Un seul commit à la fin, message en français, au format « refactor: … » ou « feat(ui): … ».
- À la fin, donne-moi : liste des fichiers créés/déplacés/supprimés, résultat des tests, et tout point
  où tu as dû dévier du prompt (avec la raison).
```

---

## Prompt 0 — Préparation et filet de sécurité

```
[Bloc de contraintes communes]

Objectif : sécuriser le point de départ avant la refonte.

1. `git status` : l'arbre a des modifications non commitées (AGENTS.md, project.pbxproj, plusieurs
   fichiers Swift). Montre-moi la liste, puis commite-les telles quelles dans « chore: état avant refonte »
   (sans les fichiers de préférences Xcode utilisateur ni .DS_Store ; vérifie que .gitignore les couvre).
2. Crée la branche `refactor/clean-architecture`.
3. Supprime `default.profraw` à la racine s'il est suivi par git (il est déjà ignoré par *.profraw).
4. Lance le build + toute la suite de tests et note le résultat de référence (nombre de tests, durée).
5. Ajoute dans AGENTS.md une section « Conventions de code » reprenant : un type principal par fichier,
   injection de dépendances par protocole (pas de `.shared` dans les types métier), constantes nommées
   (pas de nombres magiques), fonctions < 30 lignes, noms qui disent l'intention, commentaires qui
   expliquent le « pourquoi » uniquement.
```

---

## Prompt 1 — Préférences centralisées (SRP + DIP)

```
[Bloc de contraintes communes]

Problème : les préférences sont éparpillées dans six enums statiques qui lisent `UserDefaults.standard`
en dur : TextCleanupPreferences, TranscriptionPreferences, HistoryPreferences, FeedbackSoundPreferences,
RecordingDurationPreferences, EmergencyHotkeyPreferences. Impossible à injecter ou à tester proprement.

Objectif : une couche Settings unique, typée et injectable.

1. Crée `DictaMac/Settings/` avec :
   - `SettingsKey.swift` : toutes les clés UserDefaults en un seul endroit (valeurs de chaîne INCHANGÉES,
     pour ne pas perdre les réglages existants des utilisateurs).
   - `SettingsStoring.swift` : protocole minimal (`func value`, `set`, `removeValue`…) + `UserDefaultsSettingsStore`
     (init avec `UserDefaults` injectable) + `InMemorySettingsStore` pour les tests.
   - Un petit protocole de lecture par domaine, adapté à ce que consomment les services (ISP) :
     `TranscriptionSettings`, `TextCleanupSettings`, `RecordingSettings`, `HistorySettings`,
     `FeedbackSoundSettings`, `EmergencyHotkeySettings`. Chaque service ne reçoit que le protocole dont il a besoin.
   - Une implémentation concrète par domaine, construite sur `SettingsStoring`. Les valeurs par défaut et la logique
     existante (migration `TextCleanupPreferences.migrate`, repli du mode sûr `SafeModeState`, détection
     `isLowMemoryMac`, valeur par défaut « true » de removeIsolatedGenre) sont préservées à l'identique.
2. Remplace tous les usages des anciens enums par l'injection des protocoles dans les initialiseurs
   (valeurs par défaut `= UserDefaultsSettings…()` tolérées pour les call-sites existants dans cette étape).
3. Les vues SwiftUI gardent `@AppStorage` pour l'instant (elles seront refaites au prompt 6) mais doivent
   utiliser les constantes de `SettingsKey`, jamais de chaînes littérales.
4. Supprime les anciens enums une fois migrés. `grep UserDefaults.standard` ne doit plus matcher que
   `UserDefaultsSettingsStore` et le composition root.
5. Tests : migration des moteurs de nettoyage, valeurs par défaut, repli mode sûr, via `InMemorySettingsStore`.
```

---

## Prompt 2 — Un type par fichier + moteurs de nettoyage ouverts à l'extension (SRP + OCP)

```
[Bloc de contraintes communes]

Problème : plusieurs fichiers regroupent des responsabilités sans rapport.
- TextCleanupService.swift : protocole, enum de moteurs, préférences, règles rapides, post-processeur,
  Keychain de clé API, service cloud, sélecteur `ConfiguredTextCleanupService` (switch fermé).
- LocalTextCleanupService.swift (473 l.) : état observable, manager de modèle (actor), erreurs, service.
- DictationDiagnostics.swift (428 l.) et EmergencyWatchdog.swift (377 l.) : 6 à 8 types chacun.
- TranscriptionService.swift : protocole, préférences, état observable, erreurs, service WhisperKit.

Objectif : un type principal par fichier, dossiers par fonctionnalité, et sélection de moteur extensible.

1. Découpe chaque fichier ci-dessus en fichiers nommés d'après leur type, rangés par sous-dossier
   (ex. `TextCleanup/Engines/`, `TextCleanup/Local/`, `Diagnostics/Emergency/`, `Diagnostics/Logging/`).
   Déplacement quasi mécanique : pas de logique modifiée. Garde les `private` qui deviennent `fileprivate`
   ou internes seulement si nécessaire.
2. Remplace le `switch` de `ConfiguredTextCleanupService` par un registre injecté :
   `TextCleanupEngineRegistry` (dictionnaire `TextCleanupEngine -> any TextCleanupService`) construit dans le
   composition root. Ajouter un moteur ne doit plus nécessiter de modifier le sélecteur (Open/Closed).
   Le cas `.disabled` devient un service « identité » (`PassthroughTextCleanupService`).
3. Retire les singletons statiques `static let shared` des services de nettoyage au profit d'instances
   injectées par le registre. Le comportement (moteur lu à chaque appel via `TextCleanupSettings`) reste identique.
4. Vérifie chaque nom de fichier ↔ type, et qu'aucun fichier ne dépasse ~250 lignes ; sinon redécoupe.
```

---

## Prompt 3 — Refonte de DictationCoordinator (SRP, DIP, DRY)

```
[Bloc de contraintes communes]

Problème : DictationCoordinator (460 l.) fait tout. Il dépend de types concrets (HotkeyService,
AudioRecorder, DictationOverlayController) et de ~32 accès à des singletons (PersistentDiagnosticLog.shared,
EmergencyRuntime.shared, TranscriptionHistoryStore.shared, DictationDiagnostics.shared,
LocalCleanupModelManager.shared, WhisperKitTranscriptionService.shared…). Les trois étapes
transcription / nettoyage / injection répètent le même bloc : stage(begin) + EmergencyRuntime.begin +
signpost + do/catch + signpost end + stage(end) + EmergencyRuntime.end.

Objectif : un coordinateur mince qui orchestre ; chaque responsabilité dans son type, derrière un protocole.

1. Protocoles (DIP) dans `Coordination/Protocols/`, avec les implémentations existantes comme conformances :
   `HotkeyProviding` (onPress/onRelease/onCancel, start/stop), `AudioRecording` (start, stop, capturedSamples,
   lastRecordingDuration, onLevelUpdate, onError), `OverlayPresenting` (showRecording, updateLevel,
   showTranscribing, showMessage, showError, hide), `FeedbackSoundPlaying`, `DictationHistoryRecording`,
   `DictationMetricsRecording`, `DictationStageReporting` (logs persistants + EmergencyRuntime + signposts).
2. Extrais `InstrumentedStage` : une fonction générique
   `func run<T>(_ stage: DiagnosticStage, context: StageContext, _ work: () async throws -> T) async throws -> T`
   qui encapsule begin/end, signpost, EmergencyRuntime et garantit la fermeture en cas d'erreur/annulation.
   Les trois blocs dupliqués du coordinateur disparaissent.
3. Extrais `DictationPipeline` (struct/actor) : reçoit les samples + session, exécute
   transcription → nettoyage (avec repli sur le texte brut si erreur, hors timeout watchdog) → injection →
   historique → métriques, et retourne un `DictationOutcome` (enum : `.inserted`, `.copiedToClipboard`,
   `.partial`, `.empty`, `.cancelled`, `.failed(PipelineFailure)`). Plus aucune présentation d'overlay à l'intérieur.
4. Extrais `RecordingSession` : possède la boucle d'alimentation (50 ms), le minuteur de durée maximale et
   le `SegmentedTranscriber` actif ; expose `start()`, `finish()`, `cancel()`. Remplace les Task optionnels
   dispersés (audioFeedTask, maximumDurationTask, activeSegmentedTranscriber) par un seul objet,
   et simplifie `refreshEmergencyCancellationHandlers`.
5. `DictationCoordinator` ne garde que : machine à états (`DictationSessionPolicy`), branchement des
   événements hotkey/erreurs audio, et traduction `DictationOutcome` → appels à `OverlayPresenting`.
   Chaque méthode < 30 lignes. Le `defer`/nettoyage de fin de session est factorisé en une seule méthode.
6. Constantes nommées pour : 8 s de budget de transcription finale, 4 s par segment estimé, 50 ms de période
   d'alimentation, 1 s de délai avant activation MLX, 2 s d'affichage des messages.
7. Tests (avec des fakes des protocoles) : appui/relâchement nominal, annulation en cours d'enregistrement,
   durée maximale, repli du nettoyage, entrée audio perdue, appui court ignoré. Le coordinateur doit être
   testable SANS micro, SANS WhisperKit, SANS UI.
```

---

## Prompt 4 — Composition root et AppDelegate allégé (DIP, SRP)

```
[Bloc de contraintes communes]

Problème : AppDelegate (dans DictaMacApp.swift) gère le lancement, la fin, le heartbeat, le mode sûr (avec
NSAlert), la pression mémoire (avec NSAlert) et construit lui-même le coordinateur avec les singletons.

Objectif : un point unique d'assemblage et des responsabilités séparées.

1. Crée `App/AppEnvironment.swift` (composition root) : seul endroit qui instancie les implémentations
   concrètes (stores de réglages, services, registre de nettoyage, pipeline, coordinateur) et les passe
   explicitement. Les derniers `.shared` des types métier disparaissent ; ne restent que ceux strictement
   imposés par le système (ex. NSWorkspace) ou tolérés dans AppEnvironment.
2. Extrais de l'AppDelegate : `MemoryPressureMonitor` (source + décharge des modèles + repli sur le
   nettoyage Rapide), `SafeModeLauncher` (détection de sortie anormale + alerte), `MainThreadHeartbeat`.
   Les `NSAlert` passent derrière un protocole `UserAlertPresenting` pour être testables.
3. Fichiers : `App/DictaMacApp.swift` ne contient que le `@main` et les scènes ; `MenuBarContent` va
   dans `UI/MenuBar/`. L'AppDelegate < 60 lignes, ne fait que déléguer.
4. Garde la garde `XCTestConfigurationFilePath` pour ne rien démarrer pendant les tests.
5. Tests : `MemoryPressureMonitor` avec un décharge-modèle factice (warning vs critical).
```

---

## Prompt 5 — Design system + overlay d'enregistrement

```
[Bloc de contraintes communes — ici seul l'aspect visuel peut changer]

Direction artistique : natif macOS soigné, moderne, épuré. Matériaux translucides, SF Symbols, peu de
couleurs (une seule couleur d'accent système), beaucoup d'espace, typographie système (SF) avec hiérarchie nette.
Pas de dégradés criards, pas d'ombres lourdes. Support clair/sombre, Dynamic Type quand pertinent,
Réduire les animations (`accessibilityReduceMotion`) et contraste élevé respectés.

1. Crée `UI/DesignSystem/` :
   - `Theme.swift` : tokens (espacements 4/8/12/16/24, rayons, tailles de police sémantiques, durées/courbes
     d'animation), aucune valeur magique dans les vues.
   - Composants réutilisables : `SettingsCard` (section regroupée avec titre et pied de page), `SettingsRow`
     (libellé + description + contrôle), `StatusBadge` (prêt / chargement / erreur), `PrimaryButtonStyle`/
     `SecondaryButtonStyle`, `InfoCallout` (info / avertissement).
2. Refais l'overlay (`UI/Overlay/`), en gardant INTACT son comportement : panneau non activant, au-dessus
   des autres fenêtres, `ignoresMouseEvents`, présent sur tous les espaces, positionné au bas de l'écran du curseur.
   - Sépare `DictationOverlayController` (fenêtre/positionnement), `DictationOverlayModel` (état) et les vues
     (`RecordingPill`, `TranscribingPill`, `MessagePill`) chacune dans son fichier ; le controller implémente `OverlayPresenting`.
   - Pilule plus compacte et épurée (≈ 200×44), matériau `.regularMaterial`, bord 0,5 pt subtil, ombre très légère.
   - Enregistrement : point d'état rouge qui pulse doucement, forme d'onde fluide (barres arrondies, animation
     par ressort) alimentée par le niveau audio, libellé court. Transcription : indicateur discret + message.
     Message/erreur : icône SF Symbol + texte, teinte sémantique douce.
   - Transitions entre états animées (opacité + léger scale), désactivées si Réduire les animations.
   - Libellés d'accessibilité corrects pour chaque état.
3. Ajoute des previews SwiftUI pour chaque état (`#Preview`).
```

---

## Prompt 6 — Refonte de la fenêtre Réglages

```
[Bloc de contraintes communes — ici seul l'aspect visuel et la structure des vues changent]

Problème : SettingsView (501 l.) = tout dans un seul type, ~25 @AppStorage, un long ScrollView.

Objectif : une fenêtre Réglages moderne, façon Réglages Système, découpée en vues et view models.

1. Structure : `NavigationSplitView` (ou sidebar équivalente) avec les sections Général, Transcription,
   Nettoyage du texte, Autorisations, Diagnostic. Fenêtre ≈ 720×520, redimensionnable en hauteur.
   Chaque section = un fichier dans `UI/Settings/<Section>/` : `<Section>SettingsView` + `<Section>SettingsViewModel`
   (`@MainActor`, `ObservableObject`) qui dépend des protocoles de réglages du prompt 1, jamais de UserDefaults.
2. Utilise les composants du design system (SettingsCard / SettingsRow / StatusBadge / InfoCallout). Un titre
   et une phrase d'aide par carte ; les textes d'aide longs actuels sont raccourcis sans perdre d'information utile.
3. Nettoyage du texte : sélecteur segmenté Désactivé / Rapide / Local / Cloud ; les options propres à chaque
   moteur n'apparaissent que pour le moteur choisi, avec transition douce. État du modèle local (téléchargement,
   prêt, erreur) via `StatusBadge` + barre de progression fine. Clé API : champ sécurisé + bouton Enregistrer,
   statut clair, Keychain inchangé.
4. Autorisations : une ligne par permission avec pastille d'état (accordée / à accorder) et bouton d'action direct.
5. Diagnostic : mesures de la dernière dictée sous forme de petite table alignée ; benchmark visible uniquement en DEBUG.
6. Le `.onChange(of: textCleanupEngine)` qui approuve/décharge le modèle local passe dans le view model du nettoyage.
7. Aucune chaîne de clé littérale dans les vues ; aucun nombre magique ; previews pour chaque section avec un
   `InMemorySettingsStore`.
```

---

## Prompt 7 — Menu de la barre, finitions clean code, doc

```
[Bloc de contraintes communes]

1. Menu de la barre : passe `MenuBarExtra` en `.menuBarExtraStyle(.window)` et crée un panneau épuré
   (`UI/MenuBar/`) : en-tête avec nom + état global (Whisper prêt / LLM local), liste compacte des dernières
   dictées (clic = copier, retour visuel « Copié »), pied avec « Réglages… » et « Quitter ». Icône de barre
   de menus qui reflète l'état (repos / enregistrement / transcription) via SF Symbols. Même design system.
2. Passe clean code sur tout le dépôt :
   - recherche des nombres/chaînes magiques restants → constantes nommées ;
   - fonctions > 30 lignes → découpées ; paramètres > 4 → regroupés dans un type ;
   - `@unchecked Sendable` : pour chacun, soit le remplacer par un acteur / un type réellement Sendable, soit
     documenter en commentaire l'invariant qui justifie le `@unchecked` ;
   - code mort et imports inutiles supprimés ;
   - chaînes utilisateur centralisées dans un `Localizable.xcstrings` (français par défaut) si cela reste sans
     risque ; sinon dans une enum `L10n` simple.
3. Documentation : mets à jour README.md et la section « Architecture actuelle » d'AGENTS.md pour refléter
   la nouvelle arborescence (Settings, Coordination/Protocols, Pipeline, AppEnvironment, DesignSystem) et
   ajoute un schéma Mermaid des dépendances (UI → ViewModels → protocoles ← services ; AppEnvironment assemble).
4. Vérification finale : build complet (demande-moi avant), toute la suite de tests, `grep` de contrôle :
   plus de `UserDefaults.standard` hors store, plus de `.shared` dans les types métier, aucun fichier > 250 lignes
   sans justification. Résume les écarts restants dans `docs/refactor-notes.md`.
```
