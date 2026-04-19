import XCTest
@testable import CactusVoice

final class PairingStoreTests: XCTestCase {

    func testParseValidQRPayload() {
        let qr = "cactus://pair?ip=192.168.1.42&port=8731&token=abc123xyz"
        let pairing = PairingStore.parse(qrPayload: qr)
        XCTAssertNotNil(pairing)
        XCTAssertEqual(pairing?.host, "192.168.1.42")
        XCTAssertEqual(pairing?.port, 8731)
        XCTAssertEqual(pairing?.token, "abc123xyz")
    }

    func testParseRejectsWrongScheme() {
        XCTAssertNil(PairingStore.parse(qrPayload: "https://pair?ip=10.0.0.1&port=80&token=t"))
    }

    func testParseRejectsMissingFields() {
        XCTAssertNil(PairingStore.parse(qrPayload: "cactus://pair?port=8731&token=x"))
        XCTAssertNil(PairingStore.parse(qrPayload: "cactus://pair?ip=10.0.0.1&token=x"))
        XCTAssertNil(PairingStore.parse(qrPayload: "cactus://pair?ip=10.0.0.1&port=80"))
    }

    func testParseRejectsBadPort() {
        XCTAssertNil(PairingStore.parse(qrPayload: "cactus://pair?ip=10.0.0.1&port=notanumber&token=t"))
    }

    func testBaseURLConstruction() {
        let p = PairedMac(host: "10.0.0.5", port: 8731, token: "t")
        XCTAssertEqual(p.baseURL?.absoluteString, "http://10.0.0.5:8731")
    }
}
