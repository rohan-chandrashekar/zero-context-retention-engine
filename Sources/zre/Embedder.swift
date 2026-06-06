import Foundation
import CoreML
import CoreVideo

enum EmbedderError: Error {
    case modelNotFound(String)
    case missingOutput(String)
}

final class Embedder {
    private let model: MLModel
    private let inputName: String
    private let outputName: String

    init(modelPath: String, computeUnits: MLComputeUnits, inputName: String = "image", outputName: String = "embedding") throws {
        let url = URL(fileURLWithPath: modelPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EmbedderError.modelNotFound(modelPath)
        }

        let compiledURL: URL
        if url.pathExtension == "mlmodelc" {
            compiledURL = url
        } else {
            compiledURL = try MLModel.compileModel(at: url)
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        self.inputName = inputName
        self.outputName = outputName
    }

    func embed(_ pixelBuffer: CVPixelBuffer) throws -> [Float] {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            inputName: MLFeatureValue(pixelBuffer: pixelBuffer)
        ])
        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
            throw EmbedderError.missingOutput(outputName)
        }
        return Embedder.floatArray(from: array)
    }

    private static func floatArray(from array: MLMultiArray) -> [Float] {
        let count = array.count
        var result = [Float](repeating: 0, count: count)
        switch array.dataType {
        case .float32:
            let pointer = array.dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<count { result[i] = pointer[i] }
        case .double:
            let pointer = array.dataPointer.assumingMemoryBound(to: Double.self)
            for i in 0..<count { result[i] = Float(pointer[i]) }
        case .float16:
            #if arch(arm64)
            let pointer = array.dataPointer.assumingMemoryBound(to: Float16.self)
            for i in 0..<count { result[i] = Float(pointer[i]) }
            #else
            for i in 0..<count { result[i] = array[i].floatValue }
            #endif
        case .int32:
            let pointer = array.dataPointer.assumingMemoryBound(to: Int32.self)
            for i in 0..<count { result[i] = Float(pointer[i]) }
        case .int8:
            let pointer = array.dataPointer.assumingMemoryBound(to: Int8.self)
            for i in 0..<count { result[i] = Float(pointer[i]) }
        @unknown default:
            for i in 0..<count { result[i] = array[i].floatValue }
        }
        return result
    }
}
