import Foundation
import CryptoKit
import ZIPFoundation

enum ModelDownloadEvent: Equatable {
    case progress(Double)
    case extracting
    case completed(URL)
    case failed(String)
}

enum ModelStorage {
    static var modelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("models", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func modelDir(for model: ModelEntry) -> URL {
        modelsDirectory.appendingPathComponent(model.modelDirName, isDirectory: true)
    }

    static func configPath(for model: ModelEntry) -> URL {
        modelDir(for: model).appendingPathComponent("config.txt")
    }

    static func isPresent(_ model: ModelEntry) -> Bool {
        FileManager.default.fileExists(atPath: configPath(for: model).path)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func unzip(_ zipURL: URL, into destDir: URL) throws {
        if FileManager.default.fileExists(atPath: destDir.path) {
            try FileManager.default.removeItem(at: destDir)
        }
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: zipURL, to: destDir)

        let contents = (try? FileManager.default.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil)) ?? []
        if contents.count == 1, contents[0].hasDirectoryPath {
            let inner = contents[0]
            let innerContents = try FileManager.default.contentsOfDirectory(at: inner, includingPropertiesForKeys: nil)
            for item in innerContents {
                let dest = destDir.appendingPathComponent(item.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: item, to: dest)
            }
            try? FileManager.default.removeItem(at: inner)
        }
    }
}

final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: AsyncStream<ModelDownloadEvent>.Continuation?
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private let model: ModelEntry
    private let huggingfaceToken: String?

    init(model: ModelEntry, huggingfaceToken: String? = nil) {
        self.model = model
        self.huggingfaceToken = huggingfaceToken
        super.init()
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = false
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 3600
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func cancel() {
        task?.cancel()
        continuation?.finish()
    }

    func download() -> AsyncStream<ModelDownloadEvent> {
        AsyncStream { cont in
            self.continuation = cont
            var req = URLRequest(url: model.downloadURL)
            if let token = huggingfaceToken, !token.isEmpty {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let task = session.downloadTask(with: req)
            self.task = task
            task.resume()
            cont.onTermination = { [weak self] _ in
                self?.task?.cancel()
            }
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : model.approxBytes
        let p = min(1.0, max(0.0, Double(totalBytesWritten) / Double(total)))
        continuation?.yield(.progress(p))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let zipDest = ModelStorage.modelsDirectory.appendingPathComponent("\(model.id).zip")
        let modelDir = ModelStorage.modelDir(for: model)
        do {
            if FileManager.default.fileExists(atPath: zipDest.path) {
                try FileManager.default.removeItem(at: zipDest)
            }
            try FileManager.default.moveItem(at: location, to: zipDest)

            if let expected = model.sha256 {
                let actual = try ModelStorage.sha256(of: zipDest)
                guard actual.lowercased() == expected.lowercased() else {
                    try? FileManager.default.removeItem(at: zipDest)
                    continuation?.yield(.failed("sha256 mismatch (expected \(expected), got \(actual))"))
                    continuation?.finish()
                    return
                }
            }

            continuation?.yield(.extracting)
            try ModelStorage.unzip(zipDest, into: modelDir)
            try? FileManager.default.removeItem(at: zipDest)

            guard FileManager.default.fileExists(atPath: ModelStorage.configPath(for: model).path) else {
                continuation?.yield(.failed("config.txt missing after unzip at \(modelDir.path)"))
                continuation?.finish()
                return
            }

            continuation?.yield(.completed(modelDir))
            continuation?.finish()
        } catch {
            continuation?.yield(.failed(error.localizedDescription))
            continuation?.finish()
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            continuation?.yield(.failed(error.localizedDescription))
            continuation?.finish()
        }
    }
}
