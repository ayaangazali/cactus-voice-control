import Foundation

struct ModelEntry: Identifiable, Equatable, Hashable {
    enum Kind: String, Codable { case llm, transcription }

    let id: String
    let displayName: String
    let kind: Kind
    let huggingfaceRepo: String
    let weightZipPath: String
    let modelDirName: String
    let approxBytes: Int64
    let sha256: String?
    let minRamMB: Int
    let isGated: Bool

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(huggingfaceRepo)/resolve/main/\(weightZipPath)")!
    }
}

enum ModelCatalog {
    static let qwen3_1_7b = ModelEntry(
        id: "qwen3-1.7b-int4",
        displayName: "Qwen3 1.7B (INT4)",
        kind: .llm,
        huggingfaceRepo: "Cactus-Compute/Qwen3-1.7B",
        weightZipPath: "weights/qwen3-1.7b-int4.zip",
        modelDirName: "Qwen3-1.7B-int4",
        approxBytes: 1_006_051_493,
        sha256: "a9d09c15110b2977f6b71d393bbad4f9991b5d59638c413ea07c63d2c28ca802",
        minRamMB: 1500,
        isGated: false
    )

    static let gemma3_1b = ModelEntry(
        id: "gemma3-1b-int4",
        displayName: "Gemma 3 1B (INT4)",
        kind: .llm,
        huggingfaceRepo: "Cactus-Compute/gemma-3-1b-it",
        weightZipPath: "weights/gemma-3-1b-it-int4.zip",
        modelDirName: "gemma-3-1b-it-int4",
        approxBytes: 653_364_910,
        sha256: "bfa47bd9589d6ee97f21474dc7965fde98d71e4c21e25fc863b9acb00cf29bbf",
        minRamMB: 1200,
        isGated: false
    )

    static let whisperBase = ModelEntry(
        id: "whisper-base-int4-apple",
        displayName: "Whisper Base (INT4 NPU)",
        kind: .transcription,
        huggingfaceRepo: "Cactus-Compute/whisper-base",
        weightZipPath: "weights/whisper-base-int4-apple.zip",
        modelDirName: "whisper-base-int4-apple",
        approxBytes: 85_018_505,
        sha256: "c4da0c5ba09d3036b02585980f1893118f6824143edd1ddb819f821a031a9b4b",
        minRamMB: 256,
        isGated: false
    )

    static let llmModels: [ModelEntry] = [qwen3_1_7b, gemma3_1b]
    static let transcriptionModels: [ModelEntry] = [whisperBase]
    static let allRequired: [ModelEntry] = [whisperBase, qwen3_1_7b, gemma3_1b]
}
