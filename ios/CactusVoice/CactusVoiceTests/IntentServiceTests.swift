import XCTest
@testable import CactusVoice

final class IntentServiceTests: XCTestCase {

    func testPreprocessStripsThinkBlock() {
        let input = "<think>I am thinking</think>{\"x\":1}"
        let out = IntentService.preprocess(input)
        XCTAssertFalse(out.contains("<think>"))
        XCTAssertTrue(out.contains("{\"x\":1}"))
    }

    func testPreprocessStripsCodeFences() {
        let input = "```json\n{\"a\":2}\n```"
        let out = IntentService.preprocess(input)
        XCTAssertFalse(out.contains("```"))
        XCTAssertTrue(out.contains("\"a\":2"))
    }

    func testExtractJSONBalancedFirstObject() {
        let raw = "lead {\"a\":{\"b\":1}} trail {\"c\":2}"
        let json = IntentService.extractJSON(from: raw)
        XCTAssertEqual(json, "{\"a\":{\"b\":1}}")
    }

    func testExtractJSONOnPureJSON() {
        let raw = "{\"instruction\":\"x\"}"
        XCTAssertEqual(IntentService.extractJSON(from: raw), raw)
    }

    func testExtractJSONReturnsTextWhenNoBraces() {
        XCTAssertEqual(IntentService.extractJSON(from: "no json here"), "no json here")
    }

    func testDecodeIntentValid() throws {
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
        XCTAssertThrowsError(try IntentService.decodeIntent(json: "not json", transcript: "x", modelId: "y"))
    }

    func testDecodeIntentRejectsEmptyInstruction() {
        let json = "{\"instruction\":\"   \"}"
        XCTAssertThrowsError(try IntentService.decodeIntent(json: json, transcript: "x", modelId: "y"))
    }

    func testDecodeIntentTreatsEmptyOutputDescAsNil() throws {
        let json = "{\"instruction\":\"x\",\"output_description\":\"   \"}"
        let intent = try IntentService.decodeIntent(json: json, transcript: "x", modelId: "y")
        XCTAssertNil(intent.outputDescription)
    }
}
