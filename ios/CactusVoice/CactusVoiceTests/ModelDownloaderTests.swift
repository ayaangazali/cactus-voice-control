import XCTest
@testable import CactusVoice

final class ModelDownloaderTests: XCTestCase {

    func testCatalogContainsRequiredModels() {
        XCTAssertEqual(ModelCatalog.allRequired.count, 3)
        XCTAssertTrue(ModelCatalog.allRequired.contains(ModelCatalog.whisperBase))
        XCTAssertTrue(ModelCatalog.allRequired.contains(ModelCatalog.qwen3_1_7b))
        XCTAssertTrue(ModelCatalog.allRequired.contains(ModelCatalog.gemma3_1b))
    }

    func testHuggingFaceURLConstruction() {
        let url = ModelCatalog.qwen3_1_7b.downloadURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "huggingface.co")
        XCTAssertTrue(url.path.contains("Cactus-Compute/Qwen3-1.7B"))
        XCTAssertTrue(url.path.hasSuffix(".zip"))
    }

    func testNoneOfDefaultModelsAreGated() {
        // We dropped Gemma 4B (gated) in favor of Gemma 3 1B (ungated).
        for model in ModelCatalog.allRequired {
            XCTAssertFalse(model.isGated, "\(model.id) should not be gated")
        }
    }

    func testStoragePathsAreUnique() {
        let urls = ModelCatalog.allRequired.map { ModelStorage.modelDir(for: $0) }
        XCTAssertEqual(Set(urls).count, urls.count)
        for url in urls {
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "models")
        }
    }

    func testConfigPathInsideModelDir() {
        let cfg = ModelStorage.configPath(for: ModelCatalog.qwen3_1_7b)
        XCTAssertEqual(cfg.lastPathComponent, "config.txt")
        XCTAssertEqual(cfg.deletingLastPathComponent(), ModelStorage.modelDir(for: ModelCatalog.qwen3_1_7b))
    }

    func testSHA256OfTempFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cactus-test-\(UUID().uuidString)")
        let payload = "hello cactus".data(using: .utf8)!
        try payload.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let hash = try ModelStorage.sha256(of: tmp)
        XCTAssertEqual(hash.count, 64)
        // Deterministic: SHA-256("hello cactus") = e3...
        XCTAssertTrue(hash.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
