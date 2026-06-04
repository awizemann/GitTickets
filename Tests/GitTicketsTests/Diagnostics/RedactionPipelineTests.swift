import XCTest
@testable import GitTickets

final class RedactionPipelineTests: XCTestCase {

    func test_emailReplacementSingleAndMultiple() {
        let input = "Contact: a@b.com or admin@example.org for help."
        let output = RedactionPipeline.redact(input, with: [.email])
        XCTAssertEqual(output, "Contact: [email redacted] or [email redacted] for help.")
    }

    func test_emailReplacementHandlesPlusAndDots() {
        let input = "a.b+test@foo.example.com"
        let output = RedactionPipeline.redact(input, with: [.email])
        XCTAssertEqual(output, "[email redacted]")
    }

    func test_ipv4Replacement() {
        let input = "Connecting to 192.168.1.1 and 8.8.8.8 ..."
        let output = RedactionPipeline.redact(input, with: [.ipv4])
        XCTAssertEqual(output, "Connecting to [ip redacted] and [ip redacted] ...")
    }

    func test_ipv6Replacement() {
        let input = "Source 2001:db8::1 dropped"
        let output = RedactionPipeline.redact(input, with: [.ipv6])
        XCTAssertTrue(output.contains("[ip redacted]"))
        XCTAssertFalse(output.contains("2001:db8"))
    }

    func test_bearerTokenReplacement() {
        let input = "Authorization: Bearer abcdef1234567890ABCDEF"
        let output = RedactionPipeline.redact(input, with: [.bearerToken])
        XCTAssertEqual(output, "Authorization: Bearer [token redacted]")
    }

    func test_bearerTokenIgnoresShortStrings() {
        let input = "Bearer x"
        let output = RedactionPipeline.redact(input, with: [.bearerToken])
        XCTAssertEqual(output, "Bearer x", "regex requires 16+ chars to avoid false positives")
    }

    func test_orderedApplication() {
        // Sequential pipeline: email runs first, IPv4 second.
        let input = "Send 1.2.3.4 to admin@example.com"
        let output = RedactionPipeline.redact(input, with: [.email, .ipv4])
        XCTAssertEqual(output, "Send [ip redacted] to [email redacted]")
    }

    func test_emptyRedactorsLeavesTextUnchanged() {
        let input = "untouched 1.2.3.4 a@b.com"
        XCTAssertEqual(RedactionPipeline.redact(input, with: []), input)
    }

    func test_emptyInputProducesEmptyOutput() {
        XCTAssertEqual(RedactionPipeline.redact("", with: [.email, .ipv4]), "")
    }

    func test_customRedactor() {
        let pattern = try! NSRegularExpression(pattern: #"sk-[A-Z0-9]{16,}"#, options: .caseInsensitive)
        let custom = DiagnosticsRedactor(name: "openai", regex: pattern, replacement: "[openai key redacted]")
        let input = "API key: sk-abcdefghijklmnop"
        XCTAssertEqual(
            RedactionPipeline.redact(input, with: [custom]),
            "API key: [openai key redacted]"
        )
    }

    func test_realisticBlobWithEverything() {
        let input = """
        OS: iOS 17.5
        Free disk: 24.1 GB
        Recent logs:
          12:34:01 com.app.net warning: Request to 10.0.0.5 failed for user@example.com
          12:34:02 com.app.api error: Authorization: Bearer abcdef1234567890ABCDEF rejected
        """
        let output = RedactionPipeline.redact(input, with: [.email, .ipv4, .ipv6, .bearerToken])
        XCTAssertFalse(output.contains("user@example.com"))
        XCTAssertFalse(output.contains("10.0.0.5"))
        XCTAssertFalse(output.contains("abcdef1234567890ABCDEF"))
        XCTAssertTrue(output.contains("Free disk: 24.1 GB"))
    }
}
