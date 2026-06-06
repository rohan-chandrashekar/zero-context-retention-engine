import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics

enum CaptureError: Error, CustomStringConvertible {
    case noDisplays
    case displayOutOfRange(Int, Int)
    case permissionLikely(Error)

    var description: String {
        switch self {
        case .noDisplays:
            return "no displays available from ScreenCaptureKit"
        case let .displayOutOfRange(requested, available):
            return "display index \(requested) out of range; \(available) display(s) available"
        case let .permissionLikely(underlying):
            return "could not read shareable content (\(underlying)). Grant Screen Recording permission in System Settings > Privacy & Security > Screen Recording for your terminal app, then re-run."
        }
    }
}

private final class RunFlag {
    var stop = false
}

enum CaptureEngine {
    static func run(options: Options) async throws -> Stats {
        let embedder = try Embedder(modelPath: options.modelPath, computeUnits: options.computeUnits)
        let downscaler = try Downscaler(width: 256, height: 256)
        let store = try VectorStore(path: options.storePath)
        let textStore = try TextStore(path: options.textStorePath)
        let ocr = options.ocr ? OCR(accurate: options.ocrAccurate, languageCorrection: options.ocrLanguageCorrection) : nil

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            throw CaptureError.permissionLikely(error)
        }
        guard !content.displays.isEmpty else { throw CaptureError.noDisplays }
        guard options.displayIndex < content.displays.count else {
            throw CaptureError.displayOutOfRange(options.displayIndex, content.displays.count)
        }
        let display = content.displays[options.displayIndex]
        let (captureWidth, captureHeight) = captureDimensions(for: display, maxLongEdge: options.captureMaxLongEdge)

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = captureWidth
        configuration.height = captureHeight
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 5
        configuration.showsCursor = true

        let processor = FrameProcessor(
            embedder: embedder,
            downscaler: downscaler,
            ocr: ocr,
            store: store,
            textStore: textStore,
            sceneThreshold: options.sceneThreshold,
            zeroBuffers: options.zeroBuffers,
            verbose: options.verbose
        )

        let stream = SCStream(filter: filter, configuration: configuration, delegate: processor)
        let queue = DispatchQueue(label: "zre.frames")
        try stream.addStreamOutput(processor, type: .screen, sampleHandlerQueue: queue)

        try await stream.startCapture()

        let pid = ProcessInfo.processInfo.processIdentifier
        let ocrDescription = options.ocr ? (options.ocrAccurate ? "accurate" : "fast") : "off"
        FileHandle.standardError.write(Data("""
        zre capturing display \(options.displayIndex) at \(captureWidth)x\(captureHeight) -> 256x256, <=\(options.fps) fps for \(Int(options.duration)) s
        pid \(pid)  scene-threshold \(options.sceneThreshold)  zero-buffers \(options.zeroBuffers)  ocr \(ocrDescription)
        vector store \(store.path)  text store \(textStore.path)  (press Ctrl-C to stop early)
        run the zero-retention proof in another terminal: sudo bash scripts/proof_zero_retention.sh \(pid) \(Int(options.duration))

        """.utf8))

        let flag = RunFlag()
        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        signalSource.setEventHandler { flag.stop = true }
        signalSource.resume()

        let startDate = Date()
        var lastHeartbeat = Date()
        while !flag.stop && Date().timeIntervalSince(startDate) < options.duration {
            try await Task.sleep(nanoseconds: 200_000_000)
            if Date().timeIntervalSince(lastHeartbeat) >= 5 {
                lastHeartbeat = Date()
                FileHandle.standardError.write(Data("  ... complete=\(processor.stats.framesComplete) embedded=\(processor.stats.framesEmbedded) skipped=\(processor.stats.framesSkipped)\n".utf8))
            }
        }

        signalSource.cancel()
        try await stream.stopCapture()
        store.close()
        textStore.close()

        if let error = processor.streamError {
            FileHandle.standardError.write(Data("stream stopped with error: \(error)\n".utf8))
        }

        return processor.stats
    }

    private static func captureDimensions(for display: SCDisplay, maxLongEdge: Int) -> (Int, Int) {
        var width = display.width
        var height = display.height
        if let mode = CGDisplayCopyDisplayMode(display.displayID) {
            let pixelWidth = mode.pixelWidth
            let pixelHeight = mode.pixelHeight
            if pixelWidth > 0 && pixelHeight > 0 {
                width = pixelWidth
                height = pixelHeight
            }
        }
        if maxLongEdge > 0 {
            let longEdge = max(width, height)
            if longEdge > maxLongEdge {
                let scale = Double(maxLongEdge) / Double(longEdge)
                width = max(1, Int((Double(width) * scale).rounded()))
                height = max(1, Int((Double(height) * scale).rounded()))
            }
        }
        return (width, height)
    }
}
