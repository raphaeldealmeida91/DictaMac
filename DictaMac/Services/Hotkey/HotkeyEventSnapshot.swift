@preconcurrency import ApplicationServices

enum HotkeyEventKind: Sendable, Equatable {
    case flagsChanged
    case keyDown
    case systemDefined
    case tapDisabledByTimeout
    case tapDisabledByUserInput
    case other
}

struct HotkeyEventSnapshot: Sendable, Equatable {
    let kind: HotkeyEventKind
    let flags: UInt64
    let keyCode: Int64

    init(kind: HotkeyEventKind, flags: UInt64 = 0, keyCode: Int64 = -1) {
        self.kind = kind
        self.flags = flags
        self.keyCode = keyCode
    }

    init(type: CGEventType, event: CGEvent) {
        kind = Self.kind(for: type)
        flags = event.flags.rawValue
        keyCode = type == .keyDown
            ? event.getIntegerValueField(.keyboardEventKeycode)
            : -1
    }

    var fnIsDown: Bool {
        flags & CGEventFlags.maskSecondaryFn.rawValue != 0
    }

    private static func kind(for type: CGEventType) -> HotkeyEventKind {
        switch type {
        case .flagsChanged: .flagsChanged
        case .keyDown: .keyDown
        case .tapDisabledByTimeout: .tapDisabledByTimeout
        case .tapDisabledByUserInput: .tapDisabledByUserInput
        case hotkeySystemDefinedEventType: .systemDefined
        default: .other
        }
    }
}

let hotkeySystemDefinedEventType = CGEventType(rawValue: 14) ?? .null
