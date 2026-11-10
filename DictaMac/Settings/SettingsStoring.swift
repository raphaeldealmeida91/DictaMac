import Foundation

enum SettingsValue: Equatable, Sendable {
    case bool(Bool)
    case double(Double)
    case string(String)
    case stringDictionary([String: String])
}

protocol SettingsStoring: Sendable {
    func value(for key: SettingsKey) -> SettingsValue?
    func set(_ value: SettingsValue, for key: SettingsKey)
    func removeValue(for key: SettingsKey)
}

extension SettingsStoring {
    func bool(for key: SettingsKey) -> Bool? {
        guard case .bool(let value) = value(for: key) else { return nil }
        return value
    }

    func double(for key: SettingsKey) -> Double? {
        guard case .double(let value) = value(for: key) else { return nil }
        return value
    }

    func string(for key: SettingsKey) -> String? {
        guard case .string(let value) = value(for: key) else { return nil }
        return value
    }

    func stringDictionary(for key: SettingsKey) -> [String: String]? {
        guard case .stringDictionary(let value) = value(for: key) else { return nil }
        return value
    }
}

final class UserDefaultsSettingsStore: SettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func value(for key: SettingsKey) -> SettingsValue? {
        guard let object = defaults.object(forKey: key.rawValue) else { return nil }
        if let value = object as? Bool { return .bool(value) }
        if let value = object as? Double { return .double(value) }
        if let value = object as? String { return .string(value) }
        if let value = object as? [String: String] { return .stringDictionary(value) }
        return nil
    }

    func set(_ value: SettingsValue, for key: SettingsKey) {
        switch value {
        case .bool(let value): defaults.set(value, forKey: key.rawValue)
        case .double(let value): defaults.set(value, forKey: key.rawValue)
        case .string(let value): defaults.set(value, forKey: key.rawValue)
        case .stringDictionary(let value): defaults.set(value, forKey: key.rawValue)
        }
    }

    func removeValue(for key: SettingsKey) {
        defaults.removeObject(forKey: key.rawValue)
    }
}

final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [SettingsKey: SettingsValue]

    init(values: [SettingsKey: SettingsValue] = [:]) {
        self.values = values
    }

    func value(for key: SettingsKey) -> SettingsValue? {
        lock.withLock { values[key] }
    }

    func set(_ value: SettingsValue, for key: SettingsKey) {
        lock.withLock { values[key] = value }
    }

    func removeValue(for key: SettingsKey) {
        _ = lock.withLock { values.removeValue(forKey: key) }
    }
}
