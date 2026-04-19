import XCTest
@testable import CactusVoice

final class IntentServiceTests: XCTestCase {

    func testExtractJSONFromMessyOutput() {
        let raw = "Sure! Here is the JSON:\n{\"instruction\":\"open mail\",\"output_description\":null,\"urgency\":\"normal\"}\nThanks."
        let json = IntentService.extractJSON(from: raw)
        XCTAssertTrue(json.hasPrefix("{"))
        XCTAssertTrue(json.hasSuffix("}"))
    }

    func testExtractJSONOnPureJSON() {
        let raw = "{\"instruction\":\"x\"}"
        XCTAssertEqual(IntentService.extractJSON(from: raw), raw)
    }

    func testDecodeIntentFromValidJSON() throws {
        let json = "{\"instruction\":\"Open Gmail, list unread\",\"output_description\":\"JSON list\",\"urgency\":\"normal\"}"
        let intent = try IntentService.decodeIntent(json: json, transcript: "open gmail", modelId: "qwen3")
        XCTAssertEqual(intent.instruction, "Open Gmail, list unread")
        XCTAssertEqual(intent.outputDescription, "JSON list")
        XCTAssertEqual(intent.urgency, .normal)
        XCTAssertEqual(intent.rawTranscript, "open gmail")
        XCTAssertEqual(intent.modelId, "qwen3")
    }

    func testDecodeIntentDefaultsUrgencyWhenAbsent() throws {
        let json = "{\"instruction\":\"go home\"}"
        let intent = try IntentService.decodeIntent(json: json, transcript: "go home", modelId: "x")
        XCTAssertEqual(intent.urgency, .normal)
    }

    func testDecodeIntentRejectsInvalidJSON() {
        let json = "not json at all"
        XCTAssertThrowsError(try IntentService.decodeIntent(json: json, transcript: "x", modelId: "y"))
    }
}
