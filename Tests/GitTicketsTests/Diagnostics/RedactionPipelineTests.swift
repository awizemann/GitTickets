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
        let output = RedactionPipeline.redact(input, with: [.bearerToken, .email, .ipv4, .ipv6])
        XCTAssertFalse(output.contains("user@example.com"))
        XCTAssertFalse(output.contains("10.0.0.5"))
        XCTAssertFalse(output.contains("abcdef1234567890ABCDEF"))
        XCTAssertTrue(output.contains("Free disk: 24.1 GB"))
    }

    // MARK: - Regression tests for code-review findings

    /// C5: IPv4 redactor used to match four-part version strings like
    /// `1.0.0.123` wrapped in parens (`App: MyApp 1.0.0 (1.0.0.123)`),
    /// stripping the build number that triage relies on. The new regex
    /// uses paren context exclusion to avoid this.
    func test_ipv4DoesNotMatchVersionStringInParens() {
        let input = "App: MyApp 1.0.0 (1.0.0.123)"
        let output = RedactionPipeline.redact(input, with: [.ipv4])
        XCTAssertEqual(output, input)
    }

    /// C5: IPv4 still must match real addresses surrounded by typical log
    /// context (whitespace, commas, end of line).
    func test_ipv4StillMatchesRealAddresses() {
        let output = RedactionPipeline.redact("from 192.168.1.42 at 10.0.0.5,", with: [.ipv4])
        XCTAssertEqual(output, "from [ip redacted] at [ip redacted],")
    }

    /// C6: IPv6 redactor used to match HH:MM:SS clock timestamps because
    /// decimal digits are a subset of hex. New regex requires at least one
    /// A-F letter inside the match.
    func test_ipv6DoesNotMatchClockTimestamps() {
        let input = "  09:30:45 com.app warning: Something happened"
        let output = RedactionPipeline.redact(input, with: [.ipv6])
        XCTAssertEqual(output, input)
        XCTAssertTrue(output.contains("09:30:45"))
    }

    /// C6: IPv6 still must match real addresses, including loopback `::1`
    /// (the old `\b` boundary failed to match leading-`:` addresses).
    func test_ipv6MatchesLoopbackAndStandardForms() {
        XCTAssertTrue(RedactionPipeline.redact("from 2001:db8::1 ", with: [.ipv6]).contains("[ip redacted]"))
        XCTAssertTrue(RedactionPipeline.redact("from ::1 ", with: [.ipv6]).contains("[ip redacted]"))
    }

    /// C7: When bearer runs AFTER ipv4/ipv6, an embedded IP-shaped
    /// substring inside the token gets rewritten to `[ip redacted]`,
    /// breaking the bearer charset and leaking the rest of the token.
    /// The default redactor order now runs bearer first.
    func test_defaultRedactorOrderProtectsBearerWithEmbeddedIPv4() {
        let input = "Authorization: Bearer eyJhbGciOi.10.0.0.1.JzdWIiOiIxMjM0NTY3ODkw"
        let output = RedactionPipeline.redact(input, with: DiagnosticsPolicy.default.redactors)
        XCTAssertTrue(output.contains("[token redacted]"))
        XCTAssertFalse(output.contains("eyJhbGciOi"))
        XCTAssertFalse(output.contains("JzdWIiOiIxMjM0NTY3ODkw"))
    }
}
