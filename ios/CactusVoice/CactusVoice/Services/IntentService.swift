import Foundation

enum IntentServiceError: Error, LocalizedError {
    case llmFailed(String)
    case parseFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .llmFailed(let m):  return "LLM failed: \(m)"
        case .parseFailed(let m): return "JSON parse failed: \(m)"
        case .emptyTranscript:    return "Empty transcript"
        }
    }
}

final class IntentService {
    private let cactus: CactusEngine
    private let modelId: String

    init(cactus: CactusEngine, modelId: String) {
        self.cactus = cactus
        self.modelId = modelId
    }

    private static let systemPrompt = """
    You normalize a spoken transcript into a single JSON object that mobile-use can execute on an iOS Simulator.

    OUTPUT EXACTLY one JSON object, nothing else, no prose, no code fences:
    {
      "instruction": string,            // imperative sentence describing the task to perform on the phone
      "output_description": string|null, // when user wants data extracted, describe shape; otherwise null
      "urgency": "normal"|"urgent"
    }

    Examples:
    USER: open gmail and tell me my unread emails
    {"instruction":"Open Gmail and list unread emails with sender and subject","output_description":"JSON list of {sender, subject}","urgency":"normal"}

    USER: text mom i'm running late
    {"instruction":"Open Messages, find the conversation with Mom, send the message: I'm running late","output_description":null,"urgency":"normal"}

    USER: urgent uber to home now
    {"instruction":"Open Uber, request a ride to Home","output_description":null,"urgency":"urgent"}
    """

    func intent(from transcript: String) async throws -> CommandIntent {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw IntentServiceError.emptyTranscript }

        let messages: [CactusMessage] = [
            CactusMessage(role: "system", content: Self.systemPrompt),
            CactusMessage(role: "user", content: trimmed)
        ]
        var opts = CactusCompletionOptions()
        opts.maxTokens = 300
        opts.temperature = 0.2
        opts.stopSequences = ["\n\n"]

        let raw: String
        do {
            raw = try await cactus.completeOnce(messages: messages, options: opts)
        } catch {
            throw IntentServiceError.llmFailed(error.localizedDescription)
        }

        let json = Self.extractJSON(from: raw)
        return try Self.decodeIntent(json: json, transcript: trimmed, modelId: modelId)
    }

    static func extractJSON(from text: String) -> String {
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            return String(text[start...end])
        }
        return text
    }

    static func decodeIntent(json: String, transcript: String, modelId: String) throws -> CommandIntent {
        struct Payload: Decodable {
            let instruction: String
            let output_description: String?
            let urgency: String?
        }
        guard let data = json.data(using: .utf8) else {
            throw IntentServiceError.parseFailed("invalid utf8")
        }
        do {
            let p = try JSONDecoder().decode(Payload.self, from: data)
            let urgency = CommandIntent.Urgency(rawValue: p.urgency ?? "normal") ?? .normal
            return CommandIntent(
                instruction: p.instruction,
                outputDescription: p.output_description,
                urgency: urgency,
                rawTranscript: transcript,
                modelId: modelId
            )
        } catch {
            throw IntentServiceError.parseFailed(error.localizedDescription)
        }
    }
}
