import XCTest
@testable import GitTickets

final class GitTicketsSurfaceTests: XCTestCase {

    private static let testRepo = RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: .public)
    private static let testRelayURL = URL(string: "https://example.com")!
    private static let testSecret = SharedSecret(bytes: Data(repeating: 0xAB, count: 32))

    func test_configureSetsConfiguration() {
        let config = Configuration(
            repo: Self.testRepo,
            auth: .relay(url: Self.testRelayURL, sharedSecret: Self.testSecret)
        )
        GitTickets.configure(config)
        let active = GitTickets.configuration
        XCTAssertEqual(active?.repo, Self.testRepo)
    }

    func test_submitThrowsNotConfigured() async {
        let report = Report(kind: .bug, title: "Test", body: "Body")
        do {
            _ = try await GitTickets.submit(report)
            XCTFail("Expected GitTicketsError.notConfigured")
        } catch GitTicketsError.notConfigured {
            // Expected — PR 8 will wire the real submitters.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_repoCoordinateIsHashable() {
        let a = RepoCoordinate(owner: "alanw", name: "GitTickets")
        let b = RepoCoordinate(owner: "alanw", name: "GitTickets")
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func test_sharedSecretFromHex() {
        let secret = SharedSecret(hex: "deadbeef")
        XCTAssertNotNil(secret)
        XCTAssertEqual(secret?.bytes, Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func test_sharedSecretFromHexWithPrefix() {
        let secret = SharedSecret(hex: "0xdeadbeef")
        XCTAssertEqual(secret?.bytes, Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func test_sharedSecretRejectsOddLengthHex() {
        XCTAssertNil(SharedSecret(hex: "abc"))
    }

    func test_sharedSecretRejectsInvalidHex() {
        XCTAssertNil(SharedSecret(hex: "zz"))
    }

    func test_sharedSecretFromBase64() {
        let secret = SharedSecret(base64: "3q2+7w==")  // 0xde 0xad 0xbe 0xef
        XCTAssertEqual(secret?.bytes, Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func test_sharedSecretRejectsInvalidBase64() {
        XCTAssertNil(SharedSecret(base64: "!!!"))
    }

    func test_reportDefaultsGenerateSubmissionID() {
        let a = Report(kind: .bug, title: "A", body: "B")
        let b = Report(kind: .bug, title: "A", body: "B")
        XCTAssertNotEqual(a.submissionID, b.submissionID)
    }

    func test_diagnosticsPolicyDefaultsIncludeStandardRedactors() {
        let policy = DiagnosticsPolicy.default
        let names = policy.redactors.map(\.name)
        XCTAssertEqual(Set(names), Set(["email", "ipv4", "ipv6", "bearerToken"]))
    }

    func test_myIssuesPolicyDefaultsToManualRefresh() {
        XCTAssertEqual(MyIssuesPolicy.default.pollInterval, 0)
        XCTAssertEqual(MyIssuesPolicy.default.label, "gittickets")
    }

    func test_errorDescriptionsAreNonEmpty() {
        let cases: [GitTicketsError] = [
            .notConfigured,
            .signatureMismatch,
            .rateLimited(retryAfter: 60),
            .deviceFlowDenied,
            .deviceFlowExpired,
            .deviceFlowPending,
            .attachmentTooLarge(byteLimit: 5_242_880),
            .attachmentNotSupportedInDeviceFlow,
            .payloadInvalid(reason: "title empty"),
            .keychain(-25300),
        ]
        for error in cases {
            XCTAssertFalse(error.description.isEmpty, "Description empty for \(error)")
        }
    }
}
