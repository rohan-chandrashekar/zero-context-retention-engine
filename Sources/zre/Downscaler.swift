import Foundation
import Accelerate
import CoreVideo

enum DownscalerError: Error, CustomStringConvertible {
    case allocationFailed(CVReturn)

    var description: String {
        switch self {
        case let .allocationFailed(status):
            return "could not allocate downscale buffer (CVReturn \(status))"
        }
    }
}

final class Downscaler {
    let width: Int
    let height: Int
    private let destination: CVPixelBuffer

    init(width: Int = 256, height: Int = 256) throws {
        self.width = width
        self.height = height
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let allocated = buffer else {
            throw DownscalerError.allocationFailed(status)
        }
        self.destination = allocated
    }

    var output: CVPixelBuffer { destination }

    func scale(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(source, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        CVPixelBufferLockBaseAddress(destination, [])
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        guard
            let sourceBase = CVPixelBufferGetBaseAddress(source),
            let destinationBase = CVPixelBufferGetBaseAddress(destination)
        else { return nil }

        var sourceBuffer = vImage_Buffer(
            data: sourceBase,
            height: vImagePixelCount(CVPixelBufferGetHeight(source)),
            width: vImagePixelCount(CVPixelBufferGetWidth(source)),
            rowBytes: CVPixelBufferGetBytesPerRow(source)
        )
        var destinationBuffer = vImage_Buffer(
            data: destinationBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(destination)
        )

        let error = vImageScale_ARGB8888(
            &sourceBuffer,
            &destinationBuffer,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )
        return error == kvImageNoError ? destination : nil
    }
}
