import Foundation

let options = Options.parse(CommandLine.arguments)

do {
    let stats = try await CaptureEngine.run(options: options)
    Summary.print(stats: stats, options: options)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
