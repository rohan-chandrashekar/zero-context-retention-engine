import Foundation

final class Stats {
    private let lock = NSLock()
    private var completeCount = 0
    private var embeddedCount = 0
    private var skippedCount = 0
    private var latenciesMs: [Double] = []

    func recordComplete() {
        lock.lock()
        completeCount += 1
        lock.unlock()
    }

    func recordSkipped() {
        lock.lock()
        skippedCount += 1
        lock.unlock()
    }

    func recordEmbedded(latencyMs: Double) {
        lock.lock()
        embeddedCount += 1
        latenciesMs.append(latencyMs)
        lock.unlock()
    }

    var framesComplete: Int {
        lock.lock(); defer { lock.unlock() }
        return completeCount
    }

    var framesEmbedded: Int {
        lock.lock(); defer { lock.unlock() }
        return embeddedCount
    }

    var framesSkipped: Int {
        lock.lock(); defer { lock.unlock() }
        return skippedCount
    }

    var latencyCount: Int {
        lock.lock(); defer { lock.unlock() }
        return latenciesMs.count
    }

    private func sortedLatencies() -> [Double] {
        lock.lock(); defer { lock.unlock() }
        return latenciesMs.sorted()
    }

    func percentile(_ p: Double) -> Double {
        let sorted = sortedLatencies()
        guard !sorted.isEmpty else { return 0 }
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
        let sorted = sortedLatencies()
        guard !sorted.isEmpty else { return 0 }
        return sorted.reduce(0, +) / Double(sorted.count)
    }

    var skipRate: Double {
        lock.lock(); defer { lock.unlock() }
        guard completeCount > 0 else { return 0 }
        return Double(skippedCount) / Double(completeCount) * 100.0
    }
}
