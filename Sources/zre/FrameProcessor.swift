import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

final class FrameProcessor: NSObject, SCStreamOutput, SCStreamDelegate {
    let stats = Stats()
    private let embedder: Embedder
    private let downscaler: Downscaler
    private let ocr: OCR?
    private let store: VectorStore
    private let textStore: TextStore
    private let sceneThreshold: Int
    private let zeroBuffers: Bool
    private let verbose: Bool
    private var previousHash: UInt64?
    private(set) var streamError: Error?

    init(
        embedder: Embedder,
        downscaler: Downscaler,
        ocr: OCR?,
        store: VectorStore,
        textStore: TextStore,
        sceneThreshold: Int,
        zeroBuffers: Bool,
        verbose: Bool
    ) {
        self.embedder = embedder
        self.downscaler = downscaler
        self.ocr = ocr
        self.store = store
        self.textStore = textStore
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

        guard let small = downscaler.scale(pixelBuffer) else {
            if zeroBuffers { PerceptualHash.overwriteInMemory(pixelBuffer) }
            return
        }

        let hash = PerceptualHash.averageHash(small)
        let changed: Bool
        if let previous = previousHash {
            changed = PerceptualHash.hammingDistance(previous, hash) >= sceneThreshold
        } else {
            changed = true
        }
        previousHash = hash

        if !changed {
            stats.recordSkipped()
            if zeroBuffers {
                PerceptualHash.overwriteInMemory(pixelBuffer)
                PerceptualHash.overwriteInMemory(small)
            }
            return
        }

        var ocrText = ""
        var ocrMs = 0.0
        if let ocr = ocr {
            let ocrStart = CFAbsoluteTimeGetCurrent()
            ocrText = ocr.recognize(pixelBuffer)
            ocrMs = (CFAbsoluteTimeGetCurrent() - ocrStart) * 1000.0
        }

        do {
            let vector = try embedder.embed(small)
            let timestamp = Date().timeIntervalSince1970
            let index = store.recordCount
            try store.append(timestamp: timestamp, vector: vector)
            try textStore.append(index: index, timestamp: timestamp, text: ocrText)
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            stats.recordEmbedded(latencyMs: elapsedMs, ocrMs: ocrMs, chars: ocrText.count)
            if verbose {
                FileHandle.standardError.write(Data("embedded frame \(stats.framesEmbedded) in \(String(format: "%.2f", elapsedMs)) ms, ocr \(String(format: "%.2f", ocrMs)) ms, \(ocrText.count) chars\n".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("embed/store error: \(error)\n".utf8))
        }

        if zeroBuffers {
            PerceptualHash.overwriteInMemory(pixelBuffer)
            PerceptualHash.overwriteInMemory(small)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        streamError = error
    }
}
