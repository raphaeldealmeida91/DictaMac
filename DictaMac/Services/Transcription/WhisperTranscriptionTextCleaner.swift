import Foundation

enum WhisperTranscriptionTextCleaner {
    private static let hallucinatedCaptions: Set<String> = [
        "sous titrage societe radio canada",
        "sous titrage societe radio canada merci",
        "sous titres societe radio canada",
        "sous titres societe radio canada merci"
    ]

    static func clean(_ text: String) -> String {
        let artifactPattern = #"(?i)\s*[\[\(]\s*(?:blank[_ ]audio|musique|music|silence|inaudible|bruit(?: de fond)?|applaudissements?)\s*[\]\)]\s*"#
        let withoutArtifacts = text.replacingOccurrences(
            of: artifactPattern,
            with: " ",
            options: .regularExpression
        )
        let normalized = withoutArtifacts
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return isHallucinatedCaption(normalized) ? "" : normalized
    }

    private static func isHallucinatedCaption(_ text: String) -> Bool {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "fr_FR")
        )
        let wordsOnly = folded.replacingOccurrences(
            of: #"[^\p{L}\p{N}]+"#,
            with: " ",
            options: .regularExpression
        )
        let canonical = wordsOnly
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return hallucinatedCaptions.contains(canonical)
    }
}
