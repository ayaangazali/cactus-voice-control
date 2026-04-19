import Foundation

enum CactusEngineError: Error, LocalizedError {
    case modelNotLoaded
    case alreadyLoaded
    case streamNotStarted
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:    return "No model is currently loaded."
        case .alreadyLoaded:     return "A model is already loaded; unload first."
        case .streamNotStarted:  return "Streaming transcribe was not started."
        case .underlying(let m): return m
        }
    }
}

struct CactusCompletionOptions: Codable {
    var maxTokens: Int = 512
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var stopSequences: [String] = []

    enum CodingKeys: String, CodingKey {
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case stopSequences = "stop_sequences"
    }

    func toJSONString() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

struct CactusMessage: Codable {
    let role: String
    let content: String
}

actor CactusEngine {
    private var modelHandle: CactusModelT?
    private var modelPath: String?
    private var streamHandle: CactusStreamTranscribeT?

    init() {}

    var isLoaded: Bool { modelHandle != nil }
    var loadedModelPath: String? { modelPath }

    func load(modelPath: String, corpusDir: String? = nil, cacheIndex: Bool = false) throws {
        if modelHandle != nil { throw CactusEngineError.alreadyLoaded }
        let h = try cactusInit(modelPath, corpusDir, cacheIndex)
        modelHandle = h
        self.modelPath = modelPath
    }

    func unload() {
        if let s = streamHandle {
            _ = try? cactusStreamTranscribeStop(s)
            streamHandle = nil
        }
        if let h = modelHandle {
            cactusDestroy(h)
            modelHandle = nil
            modelPath = nil
        }
    }

    func reset() throws {
        guard let h = modelHandle else { throw CactusEngineError.modelNotLoaded }
        cactusReset(h)
    }

    func stop() throws {
        guard let h = modelHandle else { throw CactusEngineError.modelNotLoaded }
        cactusStop(h)
    }

    func complete(
        messages: [CactusMessage],
        options: CactusCompletionOptions = CactusCompletionOptions()
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task.detached { [weak self] in
                do {
                    guard let self else { return }
                    guard let handle = await self.modelHandle else {
                        throw CactusEngineError.modelNotLoaded
                    }
                    let messagesJson = try Self.encodeMessages(messages)
                    let optionsJson = try options.toJSONString()
                    _ = try cactusComplete(
                        handle, messagesJson, optionsJson, nil,
                        { token, _ in continuation.yield(token) },
                        nil
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func completeOnce(
        messages: [CactusMessage],
        options: CactusCompletionOptions = CactusCompletionOptions()
    ) throws -> String {
        guard let handle = modelHandle else { throw CactusEngineError.modelNotLoaded }
        let messagesJson = try Self.encodeMessages(messages)
        let optionsJson = try options.toJSONString()

        let collector = TokenCollector()
        _ = try cactusComplete(
            handle, messagesJson, optionsJson, nil,
            { token, _ in collector.append(token) },
            nil
        )
        return collector.text
    }

    private final class TokenCollector: @unchecked Sendable {
        private var buffer = ""
        private let lock = NSLock()
        func append(_ token: String) {
            lock.lock(); defer { lock.unlock() }
            buffer += token
        }
        var text: String {
            lock.lock(); defer { lock.unlock() }
            return buffer
        }
    }

    func startStreamTranscribe(language: String = "en") throws {
        guard let handle = modelHandle else { throw CactusEngineError.modelNotLoaded }
        if streamHandle != nil { throw CactusEngineError.alreadyLoaded }
        let opts = "{\"language\":\"\(language)\"}"
        streamHandle = try cactusStreamTranscribeStart(handle, opts)
    }

    func processStreamChunk(pcm: Data) throws -> String {
        guard let stream = streamHandle else { throw CactusEngineError.streamNotStarted }
        return try cactusStreamTranscribeProcess(stream, pcm)
    }

    func stopStreamTranscribe() throws -> String {
        guard let stream = streamHandle else { throw CactusEngineError.streamNotStarted }
        let final = try cactusStreamTranscribeStop(stream)
        streamHandle = nil
        return final
    }

    func transcribeOnce(pcm: Data, prompt: String? = nil, language: String = "en") throws -> String {
        guard let handle = modelHandle else { throw CactusEngineError.modelNotLoaded }
        let opts = "{\"language\":\"\(language)\"}"
        return try cactusTranscribe(handle, nil, prompt, opts, nil, pcm)
    }

    private static func encodeMessages(_ messages: [CactusMessage]) throws -> String {
        let data = try JSONEncoder().encode(messages)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
