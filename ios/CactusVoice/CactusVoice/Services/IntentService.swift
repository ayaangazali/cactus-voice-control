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
    /no_think
    You convert a transcribed voice command into ONE JSON object that drives a phone-automation agent.

    Rules:
    - Output ONE JSON object only. No prose, no code fences, no <think> tags, no explanations.
    - Always include all three keys.
    - "instruction": a clear imperative sentence (start with verb).
    - "output_description": a short shape description if user wants info extracted, else null.
    - "urgency": "urgent" if user said urgent/emergency/now-now-now/asap, else "normal".

    Examples:
    USER: open gmail and tell me my unread emails
    {"instruction":"Open Gmail and list unread emails with sender and subject","output_description":"JSON list of {sender, subject}","urgency":"normal"}

    USER: text mom i'm running late
    {"instruction":"Open Messages, find the conversation with Mom, send: I'm running late","output_description":null,"urgency":"normal"}

    USER: urgent uber to home now
    {"instruction":"Open Uber and request a ride to Home","output_description":null,"urgency":"urgent"}

    USER: open the notes app
    {"instruction":"Open the Notes app","output_description":null,"urgency":"normal"}
    """

    func intent(from transcript: String) async throws -> CommandIntent {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw IntentServiceError.emptyTranscript }

        let messages: [CactusMessage] = [
            CactusMessage(role: "system", content: Self.systemPrompt),
            CactusMessage(role: "user", content: trimmed)
        ]
        var opts = CactusCompletionOptions()
        opts.maxTokens = 256
        opts.temperature = 0.1
        opts.stopSequences = []

        let raw: String
        do {
            raw = try await cactus.completeOnce(messages: messages, options: opts)
        } catch {
            throw IntentServiceError.llmFailed(error.localizedDescription)
        }

        let cleaned = Self.preprocess(raw)
        let json = Self.extractJSON(from: cleaned)
        return try Self.decodeIntent(json: json, transcript: trimmed, modelId: modelId)
    }

    /// Strip Qwen3 <think>...</think> blocks and any markdown fences.
    static func preprocess(_ text: String) -> String {
        var t = text
        while let start = t.range(of: "<think>"),
              let end = t.range(of: "</think>", range: start.upperBound..<t.endIndex) {
            t.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // Strip ```json … ``` fences if present.
        t = t.replacingOccurrences(of: "```json", with: "")
             .replacingOccurrences(of: "```", with: "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the most plausible JSON object substring. Picks the FIRST balanced
    /// pair of `{...}` rather than greedily slicing first `{` to last `}` (which
    /// breaks when the LLM emits nested or trailing content).
    static func extractJSON(from text: String) -> String {
        var depth = 0
        var startIdx: String.Index?
        for idx in text.indices {
            let c = text[idx]
            if c == "{" {
                if depth == 0 { startIdx = idx }
                depth += 1
            } else if c == "}" {
                depth -= 1
                if depth == 0, let s = startIdx {
                    return String(text[s...idx])
                }
                if depth < 0 { depth = 0; startIdx = nil }
            }
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
            let instruction = p.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !instruction.isEmpty else {
                throw IntentServiceError.parseFailed("instruction empty")
            }
            let urgency = CommandIntent.Urgency(rawValue: p.urgency ?? "normal") ?? .normal
            let outputDesc = p.output_description?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CommandIntent(
                instruction: instruction,
                outputDescription: (outputDesc?.isEmpty == false) ? outputDesc : nil,
                urgency: urgency,
                rawTranscript: transcript,
                modelId: modelId
            )
        } catch let e as IntentServiceError {
            throw e
        } catch {
            throw IntentServiceError.parseFailed(error.localizedDescription)
        }
    }
}
