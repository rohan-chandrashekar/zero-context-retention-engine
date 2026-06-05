import Foundation

enum Summary {
    static func print(stats: Stats, options: Options) {
        let lines = """

        === Phase 1 run summary ===
        duration cap          : \(Int(options.duration)) s
        fps cap               : \(options.fps)
        scene-change threshold: \(options.sceneThreshold) bits (of 64)
        frames complete       : \(stats.framesComplete)
        frames embedded       : \(stats.framesEmbedded)
        frames skipped (gate) : \(stats.framesSkipped)
        scene-gate skip rate  : \(String(format: "%.1f", stats.skipRate)) %
        vectors stored        : \(stats.framesEmbedded)
        frame bytes to disk    : 0 by construction (no frame-write code path; verify externally with scripts/proof_zero_retention.sh)
        per-frame latency ms  : median \(String(format: "%.2f", stats.median)), p95 \(String(format: "%.2f", stats.p95)), mean \(String(format: "%.2f", stats.mean)) (n=\(stats.embedLatenciesMs.count)) [hash + embed + store]
        store path            : \(options.storePath)
        """
        FileHandle.standardOutput.write(Data((lines + "\n").utf8))
    }
}
