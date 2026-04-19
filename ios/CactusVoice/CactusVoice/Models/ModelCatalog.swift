import Foundation

struct ModelEntry: Identifiable, Equatable, Hashable {
    enum Kind: String, Codable { case llm, transcription }

    let id: String
    let displayName: String
    let kind: Kind
    let huggingfaceRepo: String
    let filename: String
    let approxBytes: Int64
    let sha256: String?
    let minRamMB: Int
    let isGated: Bool

    var downloadURL: URL {
        URL(string: "https://huggingface.co/\(huggingfaceRepo)/resolve/main/\(filename)")!
    }
}

enum ModelCatalog {
    static let qwen3_1_7b = ModelEntry(
        id: "qwen3-1.7b-int4",
        displayName: "Qwen3 1.7B (INT4)",
        kind: .llm,
        huggingfaceRepo: "Cactus-Compute/Qwen3-1.7B-Instruct-GGUF",
        filename: "Qwen3-1.7B-Instruct-Q4_K_M.gguf",
        approxBytes: 1_050_000_000,
        sha256: nil,
        minRamMB: 1500,
        isGated: false
    )

    static let gemma3_4b = ModelEntry(
        id: "gemma3-4b-int4",
        displayName: "Gemma 3 4B (INT4)",
        kind: .llm,
        huggingfaceRepo: "Cactus-Compute/gemma-3-4b-it-GGUF",
        filename: "gemma-3-4b-it-Q4_K_M.gguf",
        approxBytes: 2_500_000_000,
        sha256: nil,
        minRamMB: 4000,
        isGated: true
    )

    static let whisperBase = ModelEntry(
        id: "whisper-base-q4",
        displayName: "Whisper Base (INT4)",
        kind: .transcription,
        huggingfaceRepo: "Cactus-Compute/whisper-base-GGUF",
        filename: "whisper-base-Q4.gguf",
        approxBytes: 60_000_000,
        sha256: nil,
        minRamMB: 256,
        isGated: false
    )

    static let llmModels: [ModelEntry] = [qwen3_1_7b, gemma3_4b]
    static let transcriptionModels: [ModelEntry] = [whisperBase]
    static let allRequired: [ModelEntry] = [whisperBase, qwen3_1_7b, gemma3_4b]
}
