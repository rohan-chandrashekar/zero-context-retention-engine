import Foundation

final class Stats {
    private let lock = NSLock()
    private var completeCount = 0
    private var embeddedCount = 0
    private var skippedCount = 0
    private var latenciesMs: [Double] = []
    private var ocrLatenciesMs: [Double] = []
    private var charsRecognizedTotal = 0

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

    func recordEmbedded(latencyMs: Double, ocrMs: Double, chars: Int) {
        lock.lock()
        embeddedCount += 1
        latenciesMs.append(latencyMs)
        if ocrMs > 0 { ocrLatenciesMs.append(ocrMs) }
        charsRecognizedTotal += chars
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

    var ocrCount: Int {
        lock.lock(); defer { lock.unlock() }
        return ocrLatenciesMs.count
    }

    var charsRecognized: Int {
        lock.lock(); defer { lock.unlock() }
        return charsRecognizedTotal
    }

    private static func percentile(_ p: Double, of sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = p / 100.0 * Double(sorted.count - 1)
        let lower = Int(rank.rounded(.down))
        let upper = Int(rank.rounded(.up))
        if lower == upper { return sorted[lower] }
        let weight = rank - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    private static func mean(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    func latencyPercentile(_ p: Double) -> Double {
        lock.lock(); let sorted = latenciesMs.sorted(); lock.unlock()
        return Stats.percentile(p, of: sorted)
    }

    func ocrPercentile(_ p: Double) -> Double {
        lock.lock(); let sorted = ocrLatenciesMs.sorted(); lock.unlock()
        return Stats.percentile(p, of: sorted)
    }

    var median: Double { latencyPercentile(50) }
    var p95: Double { latencyPercentile(95) }

    var mean: Double {
        lock.lock(); let values = latenciesMs; lock.unlock()
        return Stats.mean(of: values)
    }

    var ocrMedian: Double { ocrPercentile(50) }
    var ocrP95: Double { ocrPercentile(95) }

    var ocrMean: Double {
        lock.lock(); let values = ocrLatenciesMs; lock.unlock()
        return Stats.mean(of: values)
    }

    var skipRate: Double {
        lock.lock(); defer { lock.unlock() }
        guard completeCount > 0 else { return 0 }
        return Double(skippedCount) / Double(completeCount) * 100.0
    }
}
