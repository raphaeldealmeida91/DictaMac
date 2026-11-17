import Foundation

struct DictationContext: Sendable, Equatable {
    enum UsageCategory: String, Sendable, Equatable {
        case messaging
        case email
        case document
        case code
        case other

        var promptDescription: String {
            switch self {
            case .messaging: "messagerie instantanée"
            case .email: "e-mail"
            case .document: "document"
            case .code: "code et outils de développement"
            case .other: "usage général"
            }
        }
    }

    static let maximumPrecedingCharacterCount = 300
    static let empty = DictationContext(
        bundleID: nil,
        applicationName: nil,
        category: .other,
        precedingText: ""
    )

    let bundleID: String?
    let applicationName: String?
    let category: UsageCategory
    let precedingText: String

    init(
        bundleID: String?,
        applicationName: String?,
        category: UsageCategory? = nil,
        precedingText: String = ""
    ) {
        self.bundleID = bundleID
        self.applicationName = applicationName
        self.category = category ?? Self.inferCategory(
            bundleID: bundleID,
            applicationName: applicationName
        )
        self.precedingText = String(
            precedingText.suffix(Self.maximumPrecedingCharacterCount)
        )
    }

    var continuesSentence: Bool {
        guard let last = precedingText.last(where: { !$0.isWhitespace }) else { return false }
        return !".!?…".contains(last)
    }

    var lastTwentyWords: String {
        precedingText
            .split(whereSeparator: \.isWhitespace)
            .suffix(20)
            .joined(separator: " ")
    }

    private static func inferCategory(
        bundleID: String?,
        applicationName: String?
    ) -> UsageCategory {
        let identity = [bundleID, applicationName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if containsAny(codeMarkers, in: identity) { return .code }
        if containsAny(emailMarkers, in: identity) { return .email }
        if containsAny(messagingMarkers, in: identity) { return .messaging }
        if containsAny(documentMarkers, in: identity) { return .document }
        return .other
    }

    private static func containsAny(_ markers: [String], in identity: String) -> Bool {
        markers.contains(where: identity.contains)
    }

    private static let messagingMarkers = [
        "messages", "slack", "discord", "whatsapp", "telegram", "signal", "teams", "messenger"
    ]
    private static let emailMarkers = [
        "apple.mail", "mail", "outlook", "thunderbird", "spark", "airmail"
    ]
    private static let documentMarkers = [
        "pages", "word", "notion", "obsidian", "bear", "notes", "libreoffice"
    ]
    private static let codeMarkers = [
        "xcode", "vscode", "visual studio code", "cursor", "sublime", "jetbrains", "terminal", "iterm", "warp", "zed"
    ]
}
