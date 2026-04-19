import XCTest
@testable import CactusVoice

final class TranscribeServiceTests: XCTestCase {

    func testVADFiresAboveThreshold() {
        let cfg = VADConfig(rmsThreshold: 0.01, hangoverMillis: 500, minSpeechMillis: 200)
        XCTAssertTrue(TranscribeService.vadFires(rms: 0.05, config: cfg))
        XCTAssertTrue(TranscribeService.vadFires(rms: 0.01, config: cfg))
    }

    func testVADSilentBelowThreshold() {
        let cfg = VADConfig(rmsThreshold: 0.01, hangoverMillis: 500, minSpeechMillis: 200)
        XCTAssertFalse(TranscribeService.vadFires(rms: 0.001, config: cfg))
        XCTAssertFalse(TranscribeService.vadFires(rms: 0.0, config: cfg))
    }

    func testVADConfigDefaultsAreSane() {
        let cfg = VADConfig()
        XCTAssertGreaterThan(cfg.rmsThreshold, 0)
        XCTAssertGreaterThanOrEqual(cfg.hangoverMillis, 500)
        XCTAssertGreaterThanOrEqual(cfg.minSpeechMillis, 100)
    }
}
