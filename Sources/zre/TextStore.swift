import Foundation

final class TextStore {
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

    func append(index: Int, timestamp: Double, text: String) throws {
        let record: [String: Any] = [
            "i": index,
            "t": timestamp,
            "text": text
        ]
        var line = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        line.append(0x0A)
        try handle.write(contentsOf: line)
        bytesWritten += line.count
        recordCount += 1
    }

    func close() {
        try? handle.close()
    }
}
