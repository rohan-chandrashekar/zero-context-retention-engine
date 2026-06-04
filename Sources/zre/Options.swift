import Foundation
import CoreML

struct Options {
    var duration: Double = 60
    var fps: Int = 2
    var sceneThreshold: Int = 5
    var modelPath: String = "MobileCLIPImage.mlpackage"
    var storePath: String = "vectorstore/vectors.f32bin"
    var displayIndex: Int = 0
    var computeUnits: MLComputeUnits = .all
    var zeroBuffers: Bool = true
    var verbose: Bool = false

    static func parse(_ arguments: [String]) -> Options {
        var options = Options()
        var index = 1
        let args = arguments
        func nextValue() -> String? {
            guard index + 1 < args.count else { return nil }
            index += 1
            return args[index]
        }
        while index < args.count {
            let key = args[index]
            switch key {
            case "--duration":
                if let value = nextValue(), let parsed = Double(value) { options.duration = parsed }
            case "--fps":
                if let value = nextValue(), let parsed = Int(value) { options.fps = max(1, parsed) }
            case "--scene-threshold":
                if let value = nextValue(), let parsed = Int(value) { options.sceneThreshold = parsed }
            case "--model":
                if let value = nextValue() { options.modelPath = value }
            case "--store":
                if let value = nextValue() { options.storePath = value }
            case "--display":
                if let value = nextValue(), let parsed = Int(value) { options.displayIndex = parsed }
            case "--compute":
                if let value = nextValue() {
                    switch value.lowercased() {
                    case "all": options.computeUnits = .all
                    case "cpu": options.computeUnits = .cpuOnly
                    case "gpu": options.computeUnits = .cpuAndGPU
                    case "ane", "neural": options.computeUnits = .cpuAndNeuralEngine
                    default: break
                    }
                }
            case "--no-zero":
                options.zeroBuffers = false
            case "--verbose":
                options.verbose = true
            default:
                break
            }
            index += 1
        }
        return options
    }
}
