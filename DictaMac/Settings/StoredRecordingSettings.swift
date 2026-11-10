import Foundation

struct StoredRecordingSettings: RecordingSettings {
    static let defaultMaximumDuration: TimeInterval = 120
    static let allowedRange: ClosedRange<TimeInterval> = 10...600

    private let store: any SettingsStoring

    init(store: any SettingsStoring = UserDefaultsSettingsStore()) {
        self.store = store
    }

    var maximumDuration: TimeInterval {
        let stored = store.double(for: .recordingMaximumDuration) ?? 0
        return Self.clamped(stored > 0 ? stored : Self.defaultMaximumDuration)
    }

    static func clamped(_ value: TimeInterval) -> TimeInterval {
        min(max(value, allowedRange.lowerBound), allowedRange.upperBound)
    }
}
