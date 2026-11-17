#if DEBUG
import Foundation

enum CleanupBenchmarkMetrics {
    static func normalizedEditDistance(_ lhs: String, _ rhs: String) -> Double {
        let source = Array(lhs.precomposedStringWithCanonicalMapping)
        let target = Array(rhs.precomposedStringWithCanonicalMapping)
        let denominator = max(source.count, target.count)
        guard denominator > 0 else { return 0 }
        return Double(editDistance(source, target)) / Double(denominator)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        guard sorted.count.isMultiple(of: 2) else { return sorted[middle] }
        return (sorted[middle - 1] + sorted[middle]) / 2
    }

    static func percentile95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int(ceil(Double(sorted.count) * 0.95))
        return sorted[max(0, rank - 1)]
    }

    private static func editDistance(_ source: [Character], _ target: [Character]) -> Int {
        var previous = Array(0...target.count)
        for (sourceIndex, sourceCharacter) in source.enumerated() {
            var current = [sourceIndex + 1]
            for (targetIndex, targetCharacter) in target.enumerated() {
                let substitution = previous[targetIndex] + (sourceCharacter == targetCharacter ? 0 : 1)
                current.append(min(current[targetIndex] + 1, previous[targetIndex + 1] + 1, substitution))
            }
            previous = current
        }
        return previous[target.count]
    }
}
#endif
