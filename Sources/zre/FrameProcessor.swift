import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

final class FrameProcessor: NSObject, SCStreamOutput, SCStreamDelegate {
    let stats = Stats()
    private let embedder: Embedder
    private let store: VectorStore
    private let sceneThreshold: Int
    private let zeroBuffers: Bool
    private let verbose: Bool
    private var previousHash: UInt64?
    private(set) var streamError: Error?

    init(embedder: Embedder, store: VectorStore, sceneThreshold: Int, zeroBuffers: Bool, verbose: Bool) {
        self.embedder = embedder
        self.store = store
        self.sceneThreshold = sceneThreshold
        self.zeroBuffers = zeroBuffers
        self.verbose = verbose
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        guard
            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentsArray.first,
            let statusRawValue = attachments[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue),
            status == .complete
        else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let startTime = CFAbsoluteTimeGetCurrent()
        stats.recordComplete()

        let hash = PerceptualHash.averageHash(pixelBuffer)
        let changed: Bool
        if let previous = previousHash {
            changed = PerceptualHash.hammingDistance(previous, hash) >= sceneThreshold
        } else {
            changed = true
        }
        previousHash = hash

        if !changed {
            stats.recordSkipped()
            if zeroBuffers { PerceptualHash.overwriteInMemory(pixelBuffer) }
            return
        }

        do {
            let vector = try embedder.embed(pixelBuffer)
            try store.append(timestamp: Date().timeIntervalSince1970, vector: vector)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            stats.recordEmbedded(latencyMs: elapsedMs)
            if verbose {
                FileHandle.standardError.write(Data("embedded frame \(stats.framesEmbedded) in \(String(format: "%.2f", elapsedMs)) ms\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("embed/store error: \(error)\n".utf8))
        }

        if zeroBuffers { PerceptualHash.overwriteInMemory(pixelBuffer) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        streamError = error
    }
}
