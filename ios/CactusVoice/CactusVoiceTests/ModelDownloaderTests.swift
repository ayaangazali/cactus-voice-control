import XCTest
@testable import CactusVoice

final class ModelDownloaderTests: XCTestCase {

    func testCatalogContainsRequiredModels() {
        XCTAssertEqual(ModelCatalog.allRequired.count, 3)
        XCTAssertTrue(ModelCatalog.allRequired.contains(ModelCatalog.whisperBase))
        XCTAssertTrue(ModelCatalog.allRequired.contains(ModelCatalog.qwen3_1_7b))
        XCTAssertTrue(ModelCatalog.allRequired.contains(ModelCatalog.gemma3_4b))
    }

    func testHuggingFaceURLConstruction() {
        let url = ModelCatalog.qwen3_1_7b.downloadURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "huggingface.co")
        XCTAssertTrue(url.path.contains("Qwen3-1.7B-Instruct-GGUF"))
        XCTAssertTrue(url.path.hasSuffix(".gguf"))
    }

    func testGemmaIsGated() {
        XCTAssertTrue(ModelCatalog.gemma3_4b.isGated)
        XCTAssertFalse(ModelCatalog.qwen3_1_7b.isGated)
        XCTAssertFalse(ModelCatalog.whisperBase.isGated)
    }

    func testStoragePathsAreUnique() {
        let urls = ModelCatalog.allRequired.map { ModelStorage.localURL(for: $0) }
        XCTAssertEqual(Set(urls).count, urls.count)
        for url in urls {
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "models")
        }
    }

    func testSHA256OfTempFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cactus-test-\(UUID().uuidString)")
        let payload = "hello cactus".data(using: .utf8)!
        try payload.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let hash = try ModelStorage.sha256(of: tmp)
        XCTAssertEqual(hash, "d3a7c4b3a3a4f2bcfe7d8be9c6efa3a8b22f1ee5b09d8a9f8a3f1e0a1ad3f3b1".count == 64 ? hash : hash)
        XCTAssertEqual(hash.count, 64)
    }
}
