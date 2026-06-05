import XCTest
@testable import GitTickets

final class IssueBodyBuilderTests: XCTestCase {

    private let fixedID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func makeReport(body: String = "User-written body.") -> Report {
        Report(
            kind: .bug,
            title: "Test",
            body: body,
            includeDiagnostics: true,
            deviceID: "device-1",
            submissionID: fixedID
        )
    }

    func test_minimalBodyContainsBodyAndMarker() {
        let report = makeReport()
        let output = IssueBodyBuilder.build(
            report: report,
            diagnostics: nil,
            screenshotURL: nil,
            attachments: []
        )
        XCTAssertTrue(output.contains("User-written body."))
        XCTAssertTrue(output.contains(CorrelationMarker.render(for: fixedID)))
        XCTAssertFalse(output.contains("### Diagnostics"))
        XCTAssertFalse(output.contains("### Attachments"))
    }

    func test_emptyBodyStillProducesMarker() {
        let report = makeReport(body: "")
        let output = IssueBodyBuilder.build(
            report: report,
            diagnostics: nil,
            screenshotURL: nil,
            attachments: []
        )
        XCTAssertFalse(output.isEmpty)
        XCTAssertEqual(CorrelationMarker.extract(from: output), fixedID)
    }

    func test_whitespaceOnlyBodyIsTreatedAsEmpty() {
        let output = IssueBodyBuilder.build(
            report: makeReport(body: "   \n\n   "),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: []
        )
        XCTAssertFalse(output.contains("\n\n\n"))
    }

    func test_diagnosticsRenderedInFencedBlock() {
        let diagnostics = """
        OS: iOS 17.5
        App: 1.0 (1)
        """
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: diagnostics,
            screenshotURL: nil,
            attachments: []
        )
        XCTAssertTrue(output.contains("### Diagnostics"))
        XCTAssertTrue(output.contains("```text"))
        XCTAssertTrue(output.contains("OS: iOS 17.5"))
        XCTAssertTrue(output.contains("App: 1.0 (1)"))
    }

    func test_emptyDiagnosticsSuppressesSection() {
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: "   \n   ",
            screenshotURL: nil,
            attachments: []
        )
        XCTAssertFalse(output.contains("### Diagnostics"))
    }

    func test_screenshotInlinedAsImage() {
        let url = URL(string: "https://relay.example.com/blob/abc.png")!
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: url,
            attachments: []
        )
        XCTAssertTrue(output.contains("![screenshot](https://relay.example.com/blob/abc.png)"))
    }

    func test_attachmentsRenderedAsImagesAndLinks() {
        let attachments = [
            UploadedAttachment(
                filename: "screenshot.png",
                url: URL(string: "https://relay/blob/1.png")!,
                mimeType: "image/png"
            ),
            UploadedAttachment(
                filename: "session.log",
                url: URL(string: "https://relay/blob/2.log")!,
                mimeType: "text/plain"
            ),
        ]
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: attachments
        )
        XCTAssertTrue(output.contains("### Attachments"))
        XCTAssertTrue(output.contains("![screenshot.png](https://relay/blob/1.png)"))
        XCTAssertTrue(output.contains("[session.log](https://relay/blob/2.log)"))
    }

    func test_markerIsAlwaysLast() {
        let attachments = [
            UploadedAttachment(
                filename: "a.png",
                url: URL(string: "https://x/a.png")!,
                mimeType: "image/png"
            )
        ]
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: "OS: iOS",
            screenshotURL: URL(string: "https://x/s.png")!,
            attachments: attachments
        )
        let marker = CorrelationMarker.render(for: fixedID)
        XCTAssertTrue(output.hasSuffix(marker), "Marker must be last so extractor can't trip on earlier comments")
    }

    func test_unicodeBodyPreserved() {
        let report = makeReport(body: "日本語の本文 🐛 émoji")
        let output = IssueBodyBuilder.build(
            report: report,
            diagnostics: nil,
            screenshotURL: nil,
            attachments: []
        )
        XCTAssertTrue(output.contains("日本語の本文 🐛 émoji"))
        XCTAssertEqual(CorrelationMarker.extract(from: output), fixedID)
    }

    func test_fullAssemblyRoundTripsThroughExtract() {
        let attachments = [
            UploadedAttachment(
                filename: "a.png",
                url: URL(string: "https://x/a.png")!,
                mimeType: "image/png"
            )
        ]
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: "OS: iOS 17.5\nApp: 1.0",
            screenshotURL: URL(string: "https://x/s.png")!,
            attachments: attachments
        )
        XCTAssertEqual(CorrelationMarker.extract(from: output), fixedID)
    }

    // MARK: - Regression tests for code-review findings

    /// C10: Diagnostics containing a triple-backtick must not collapse the
    /// outer fence. The builder chooses a fence longer than any inner run.
    func test_diagnosticsContainingBackticksKeepsFenceClosed() {
        let diagnostics = "User code: ```swift\nprint(\"hi\")\n```\nrest of line"
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: diagnostics,
            screenshotURL: nil,
            attachments: []
        )
        // The outer fence must be at least 4 backticks long.
        XCTAssertTrue(output.contains("````text"), "expected outer fence wider than the inner ```")
        // Inner triple-backticks must be preserved verbatim, not collapsed.
        XCTAssertTrue(output.contains("```swift"))
        // The correlation marker must still be outside any code block.
        let marker = CorrelationMarker.render(for: fixedID)
        XCTAssertTrue(output.hasSuffix(marker), "marker must remain at end and not be swallowed by a leaky fence")
    }

    /// C11: URLs containing literal `)` must be escaped so they don't
    /// terminate the markdown link early.
    func test_urlWithCloseParenIsEscaped() {
        let url = URL(string: "https://cdn.example.com/blob.png?key=a)b")!
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: url,
            attachments: []
        )
        XCTAssertTrue(output.contains("%29"), "literal `)` should be percent-encoded in markdown URL")
        XCTAssertFalse(output.contains("?key=a)b"), "raw `)` would terminate the link early")
    }
}
