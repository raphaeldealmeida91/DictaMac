import Foundation

struct DictionaryEntry: Codable, Equatable, Sendable {
    let canonical: String
    let variants: [String]

    static let defaults = [
        DictionaryEntry(
            canonical: "SFM30",
            variants: ["SFM 30", "s f m trente", "sfm30"]
        ),
        DictionaryEntry(
            canonical: "Prazo Elevator",
            variants: ["prazo elevator"]
        ),
        DictionaryEntry(
            canonical: "devis",
            variants: ["de vie"]
        ),
        DictionaryEntry(
            canonical: "ChatGPT",
            variants: ["achat de gpt", "chat gpt"]
        ),
        DictionaryEntry(canonical: "Claude", variants: []),
        DictionaryEntry(
            canonical: "Solutions 30",
            variants: ["solutions trente"]
        )
    ]
}
