import Foundation

enum CommandClientError: Error, LocalizedError {
    case notPaired
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notPaired:           return "No paired Mac. Open Settings to pair."
        case .http(let s, let m):  return "HTTP \(s): \(m)"
        case .decoding(let m):     return "Decode failed: \(m)"
        case .transport(let m):    return "Network failed: \(m)"
        }
    }
}

actor CommandClient {
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = true
        self.session = URLSession(configuration: cfg)
    }

    func ping() async throws -> Bool {
        guard let pairing = PairingStore.load(), let base = pairing.baseURL else {
            throw CommandClientError.notPaired
        }
        var req = URLRequest(url: base.appendingPathComponent("health"))
        req.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return false }
        if http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CommandClientError.http(http.statusCode, body)
        }
        return true
    }

    func send(intent: CommandIntent) async throws -> CommandStatus {
        guard let pairing = PairingStore.load(), let base = pairing.baseURL else {
            throw CommandClientError.notPaired
        }
        var req = URLRequest(url: base.appendingPathComponent("command"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.httpBody = try encoder.encode(intent)

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw CommandClientError.transport(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            throw CommandClientError.transport("no response")
        }
        guard (200...299).contains(http.statusCode) else {
            throw CommandClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(CommandStatus.self, from: data)
        } catch {
            throw CommandClientError.decoding(error.localizedDescription)
        }
    }

    func statusStream(for id: UUID) -> AsyncThrowingStream<CommandStatus, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let pairing = PairingStore.load(), let base = pairing.baseURL else {
                        throw CommandClientError.notPaired
                    }
                    var req = URLRequest(url: base.appendingPathComponent("status/\(id.uuidString)"))
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.setValue("Bearer \(pairing.token)", forHTTPHeaderField: "Authorization")
                    req.timeoutInterval = 600

                    let (bytes, resp) = try await session.bytes(for: req)
                    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                        throw CommandClientError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "stream open failed")
                    }
                    var buffer = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("data:") {
                            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            buffer = payload
                            if let data = buffer.data(using: .utf8),
                               let status = try? JSONDecoder().decode(CommandStatus.self, from: data) {
                                continuation.yield(status)
                                if status.phase == .succeeded || status.phase == .failed || status.phase == .cancelled {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
