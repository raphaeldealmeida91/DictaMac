import Foundation

enum WhisperTranscriptionTextCleaner {
    static func clean(_ text: String) -> String {
        let artifactPattern = #"(?i)\s*[\[\(]\s*(?:blank[_ ]audio|musique|music|silence|inaudible|bruit(?: de fond)?|applaudissements?)\s*[\]\)]\s*"#
        let withoutArtifacts = text.replacingOccurrences(
            of: artifactPattern,
            with: " ",
            options: .regularExpression
        )
        return withoutArtifacts
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
