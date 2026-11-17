#if DEBUG
import Foundation

enum CleanupBenchmarkMarkdownReport {
    static func render(results: [CleanupBenchmarkResult], generatedAt: Date = Date()) -> String {
        let timestamp = ISO8601DateFormatter().string(from: generatedAt)
        let rows = results.map(row).joined(separator: "\n")
        return """
        # Benchmark des modèles MLX de nettoyage

        Généré le \(timestamp) avec \(results.map(\.caseCount).max() ?? 0) cas français. Le chargement et le préchauffage sont exclus des latences. La distance d’édition normalisée est la moyenne des distances de Levenshtein divisées par la longueur maximale des deux textes. Les sorties rejetées restent incluses dans cette distance afin de ne pas masquer les erreurs par le fallback.

        | Modèle | Cas | Latence médiane | Latence p95 | Rejets validateur | Distance d’édition normalisée | État |
        |---|---:|---:|---:|---:|---:|---|
        \(rows)

        Le benchmark n’effectue aucun téléchargement. Un modèle absent de `~/Library/Application Support/DictaMac/Models/Cleanup` est ignoré.
        """
    }

    static func write(
        results: [CleanupBenchmarkResult],
        to url: URL,
        generatedAt: Date = Date()
    ) throws {
        try render(results: results, generatedAt: generatedAt).write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func row(_ result: CleanupBenchmarkResult) -> String {
        "| \(escaped(result.modelID)) | \(result.caseCount) | \(seconds(result.medianLatency)) | \(seconds(result.percentile95Latency)) | \(percent(result.validatorRejectionRate)) | \(decimal(result.normalizedEditDistance)) | \(escaped(status(result.outcome))) |"
    }

    private static func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.3f s", $0) } ?? "—"
    }

    private static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.1f %%", $0 * 100) } ?? "—"
    }

    private static func decimal(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? "—"
    }

    private static func status(_ outcome: CleanupBenchmarkResult.Outcome) -> String {
        switch outcome {
        case .completed: "Terminé"
        case .skipped(let reason): "Ignoré : \(reason)"
        case .failed(let reason): "Échec : \(reason)"
        }
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }
}
#endif
