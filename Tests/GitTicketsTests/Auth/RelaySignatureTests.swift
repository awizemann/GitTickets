import XCTest
import CryptoKit
@testable import GitTickets

final class RelaySignatureTests: XCTestCase {

    func test_signProducesStableOutput() {
        let secret = SharedSecret(bytes: Data(repeating: 0xAB, count: 32))
        let body = Data("hello".utf8)
        let first = RelaySignature.sign(timestamp: "1700000000", body: body, secret: secret)
        let second = RelaySignature.sign(timestamp: "1700000000", body: body, secret: secret)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("sha256="))
        XCTAssertEqual(first.count, "sha256=".count + 64, "SHA256 hex is 64 chars")
    }

    func test_differentTimestampsDifferentSignatures() {
        let secret = SharedSecret(bytes: Data(repeating: 0xAB, count: 32))
        let body = Data("hello".utf8)
        XCTAssertNotEqual(
            RelaySignature.sign(timestamp: "1700000000", body: body, secret: secret),
            RelaySignature.sign(timestamp: "1700000001", body: body, secret: secret)
        )
    }

    func test_differentBodiesDifferentSignatures() {
        let secret = SharedSecret(bytes: Data(repeating: 0xAB, count: 32))
        XCTAssertNotEqual(
            RelaySignature.sign(timestamp: "0", body: Data("a".utf8), secret: secret),
            RelaySignature.sign(timestamp: "0", body: Data("b".utf8), secret: secret)
        )
    }

    func test_differentSecretsDifferentSignatures() {
        let body = Data("x".utf8)
        let a = SharedSecret(bytes: Data(repeating: 0x01, count: 32))
        let b = SharedSecret(bytes: Data(repeating: 0x02, count: 32))
        XCTAssertNotEqual(
            RelaySignature.sign(timestamp: "0", body: body, secret: a),
            RelaySignature.sign(timestamp: "0", body: body, secret: b)
        )
    }

    func test_verifyMatchesSign() {
        let secret = SharedSecret(bytes: Data(repeating: 0xAA, count: 32))
        let body = Data("payload".utf8)
        let signature = RelaySignature.sign(timestamp: "42", body: body, secret: secret)
        XCTAssertTrue(RelaySignature.verify(timestamp: "42", body: body, signature: signature, secret: secret))
        XCTAssertFalse(RelaySignature.verify(timestamp: "43", body: body, signature: signature, secret: secret))
        XCTAssertFalse(RelaySignature.verify(timestamp: "42", body: Data("other".utf8), signature: signature, secret: secret))
    }

    func test_verifyTimingSafeOnLengthMismatch() {
        let secret = SharedSecret(bytes: Data(repeating: 0xAA, count: 32))
        XCTAssertFalse(RelaySignature.verify(timestamp: "0", body: Data(), signature: "sha256=short", secret: secret))
    }

    func test_signMatchesIndependentHmacComputation() {
        // Cross-check that the canonical "<ts>.<body>" input produces the same
        // HMAC we'd compute with CryptoKit directly. This is the contract the
        // relay's Node / Cloudflare implementations must match.
        let secret = SharedSecret(bytes: Data(repeating: 0x37, count: 32))
        let body = Data(#"{"hello":"world"}"#.utf8)
        let timestamp = "1700000000"

        var canonical = Data(timestamp.utf8)
        canonical.append(UInt8(ascii: "."))
        canonical.append(body)

        let mac = HMAC<SHA256>.authenticationCode(for: canonical, using: SymmetricKey(data: secret.bytes))
        let expected = "sha256=" + Data(mac).map { String(format: "%02x", $0) }.joined()

        let signed = RelaySignature.sign(timestamp: timestamp, body: body, secret: secret)
        XCTAssertEqual(signed, expected)
    }
}
