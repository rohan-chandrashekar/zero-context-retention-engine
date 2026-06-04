import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

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
        let store = try VectorStore(path: options.storePath)

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

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 256
        configuration.height = 256
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 5
        configuration.showsCursor = true

        let processor = FrameProcessor(
            embedder: embedder,
            store: store,
            sceneThreshold: options.sceneThreshold,
            zeroBuffers: options.zeroBuffers,
            verbose: options.verbose
        )

        let stream = SCStream(filter: filter, configuration: configuration, delegate: processor)
        let queue = DispatchQueue(label: "zre.frames")
        try stream.addStreamOutput(processor, type: .screen, sampleHandlerQueue: queue)

        try await stream.startCapture()

        let pid = ProcessInfo.processInfo.processIdentifier
        FileHandle.standardError.write(Data("""
        zre capturing display \(options.displayIndex) at <=\(options.fps) fps for \(Int(options.duration)) s
        pid \(pid)  scene-threshold \(options.sceneThreshold)  zero-buffers \(options.zeroBuffers)
        store \(store.path)  (press Ctrl-C to stop early)
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

        if let error = processor.streamError {
            FileHandle.standardError.write(Data("stream stopped with error: \(error)\n".utf8))
        }

        return processor.stats
    }
}
