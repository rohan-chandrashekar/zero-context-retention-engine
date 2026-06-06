import Foundation

enum Summary {
    static func print(stats: Stats, options: Options) {
        let ocrDescription = options.ocr ? (options.ocrAccurate ? "accurate" : "fast") : "off"
        let charsPerFrame = stats.framesEmbedded > 0
            ? Double(stats.charsRecognized) / Double(stats.framesEmbedded)
            : 0
        let lines = """

        === Phase 2 run summary ===
        duration cap          : \(Int(options.duration)) s
        fps cap               : \(options.fps)
        scene-change threshold: \(options.sceneThreshold) bits (of 64)
        ocr                   : \(ocrDescription)
        frames complete       : \(stats.framesComplete)
        frames embedded       : \(stats.framesEmbedded)
        frames skipped (gate) : \(stats.framesSkipped)
        scene-gate skip rate  : \(String(format: "%.1f", stats.skipRate)) %
        vectors stored        : \(stats.framesEmbedded)
        text records stored   : \(stats.framesEmbedded)
        ocr chars recognized  : \(stats.charsRecognized) total, \(String(format: "%.0f", charsPerFrame)) mean/frame
        frame bytes to disk    : 0 by construction (no frame-write code path; verify externally with scripts/proof_zero_retention.sh)
        per-frame latency ms  : median \(String(format: "%.2f", stats.median)), p95 \(String(format: "%.2f", stats.p95)), mean \(String(format: "%.2f", stats.mean)) (n=\(stats.latencyCount)) [downscale + hash + ocr + embed + store]
        ocr latency ms        : median \(String(format: "%.2f", stats.ocrMedian)), p95 \(String(format: "%.2f", stats.ocrP95)), mean \(String(format: "%.2f", stats.ocrMean)) (n=\(stats.ocrCount))
        vector store path     : \(options.storePath)
        text store path       : \(options.textStorePath)
        """
        FileHandle.standardOutput.write(Data((lines + "\n").utf8))
    }
}
