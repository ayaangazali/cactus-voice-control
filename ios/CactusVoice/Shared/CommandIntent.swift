import Foundation

struct CommandIntent: Codable, Equatable, Hashable, Identifiable {
    enum Urgency: String, Codable, CaseIterable { case normal, urgent }

    var id: UUID = UUID()
    var instruction: String
    var outputDescription: String?
    var urgency: Urgency = .normal
    var rawTranscript: String
    var modelId: String
    var createdAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id
        case instruction
        case outputDescription = "output_description"
        case urgency
        case rawTranscript = "raw_transcript"
        case modelId = "model_id"
        case createdAt = "created_at"
    }
}

struct CommandStatus: Codable, Equatable {
    enum Phase: String, Codable, CaseIterable {
        case received, running, succeeded, failed, cancelled
    }

    let id: UUID
    let phase: Phase
    let message: String?
    let result: String?
}
