import Foundation

final class VectorStore {
    private let handle: FileHandle
    let path: String
    private(set) var recordCount: Int = 0
    private(set) var bytesWritten: Int = 0

    init(path: String) throws {
        self.path = path
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        self.handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func append(timestamp: Double, vector: [Float]) throws {
        var data = Data(capacity: 8 + vector.count * 4)
        var timeBits = timestamp.bitPattern.littleEndian
        withUnsafeBytes(of: &timeBits) { data.append(contentsOf: $0) }
        for value in vector {
            var bits = value.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        try handle.write(contentsOf: data)
        bytesWritten += data.count
        recordCount += 1
    }

    func close() {
        try? handle.close()
    }
}
