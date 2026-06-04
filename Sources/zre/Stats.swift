import Foundation

final class Stats {
    var framesComplete = 0
    var framesEmbedded = 0
    var framesSkipped = 0
    var imageBytesWritten = 0
    var embedLatenciesMs: [Double] = []

    func percentile(_ p: Double) -> Double {
        guard !embedLatenciesMs.isEmpty else { return 0 }
        let sorted = embedLatenciesMs.sorted()
        let rank = p / 100.0 * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        if lower == upper { return sorted[lower] }
        let weight = rank - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    var median: Double { percentile(50) }
    var p95: Double { percentile(95) }
    var mean: Double {
        guard !embedLatenciesMs.isEmpty else { return 0 }
        return embedLatenciesMs.reduce(0, +) / Double(embedLatenciesMs.count)
    }

    var skipRate: Double {
        guard framesComplete > 0 else { return 0 }
        return Double(framesSkipped) / Double(framesComplete) * 100.0
    }
}
