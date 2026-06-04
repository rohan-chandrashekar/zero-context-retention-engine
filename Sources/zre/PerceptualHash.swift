import Foundation
import CoreVideo

enum PerceptualHash {
    static func averageHash(_ pixelBuffer: CVPixelBuffer) -> UInt64 {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        var sums = [Double](repeating: 0, count: 64)
        var counts = [Int](repeating: 0, count: 64)

        for y in 0..<height {
            let row = pixels + y * bytesPerRow
            let binY = (y * 8) / height
            for x in 0..<width {
                let pixel = row + x * 4
                let blue = Double(pixel[0])
                let green = Double(pixel[1])
                let red = Double(pixel[2])
                let luminance = 0.299 * red + 0.587 * green + 0.114 * blue
                let binX = (x * 8) / width
                let index = binY * 8 + binX
                sums[index] += luminance
                counts[index] += 1
            }
        }

        var averages = [Double](repeating: 0, count: 64)
        var mean = 0.0
        for i in 0..<64 {
            averages[i] = counts[i] > 0 ? sums[i] / Double(counts[i]) : 0
            mean += averages[i]
        }
        mean /= 64

        var hash: UInt64 = 0
        for i in 0..<64 where averages[i] > mean {
            hash |= (UInt64(1) << UInt64(i))
        }
        return hash
    }

    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    static func overwriteInMemory(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        memset(base, 0, bytesPerRow * height)
    }
}
