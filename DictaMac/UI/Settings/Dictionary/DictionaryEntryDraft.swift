import Foundation

struct DictionaryEntryDraft: Identifiable, Equatable {
    let id: UUID
    var canonical: String
    var variants: String

    init(
        id: UUID = UUID(),
        canonical: String = "",
        variants: String = ""
    ) {
        self.id = id
        self.canonical = canonical
        self.variants = variants
    }

    init(entry: DictionaryEntry) {
        self.init(
            canonical: entry.canonical,
            variants: entry.variants.joined(separator: ", ")
        )
    }
}
