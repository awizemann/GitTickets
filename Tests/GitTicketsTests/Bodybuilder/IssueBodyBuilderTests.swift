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

    // MARK: - extractUserBody round-trips

    func test_extractUserBodyFromMinimalBuild() {
        let assembled = IssueBodyBuilder.build(
            report: makeReport(body: "App crashes when I tap save."),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: []
        )
        XCTAssertEqual(IssueBodyBuilder.extractUserBody(from: assembled), "App crashes when I tap save.")
    }

    func test_extractUserBodyDropsDiagnosticsBlock() {
        let assembled = IssueBodyBuilder.build(
            report: makeReport(body: "Body before diagnostics."),
            diagnostics: "OS: macOS 26\nApp: MyApp 1.0",
            screenshotURL: nil,
            attachments: []
        )
        let extracted = IssueBodyBuilder.extractUserBody(from: assembled)
        XCTAssertEqual(extracted, "Body before diagnostics.")
        XCTAssertFalse(extracted.contains("Diagnostics"))
        XCTAssertFalse(extracted.contains("macOS 26"))
    }

    func test_extractUserBodyDropsInlineScreenshot() {
        let assembled = IssueBodyBuilder.build(
            report: makeReport(body: "Look at this."),
            diagnostics: nil,
            screenshotURL: URL(string: "https://relay.test/abc.png"),
            attachments: []
        )
        let extracted = IssueBodyBuilder.extractUserBody(from: assembled)
        XCTAssertEqual(extracted, "Look at this.")
        XCTAssertFalse(extracted.contains("relay.test"))
    }

    func test_extractUserBodyDropsAttachmentsSectionWithoutDiagnostics() {
        let attachments = [
            UploadedAttachment(
                filename: "log.txt",
                url: URL(string: "https://relay.test/log.txt")!,
                mimeType: "text/plain"
            )
        ]
        let assembled = IssueBodyBuilder.build(
            report: makeReport(body: "Body."),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: attachments
        )
        let extracted = IssueBodyBuilder.extractUserBody(from: assembled)
        XCTAssertEqual(extracted, "Body.")
        XCTAssertFalse(extracted.contains("### Attachments"))
        XCTAssertFalse(extracted.contains("log.txt"))
    }

    func test_extractUserBodyStripsMarkerOnly() {
        let bodyText = "Just body. No --- in it."
        let assembled = IssueBodyBuilder.build(
            report: makeReport(body: bodyText),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: []
        )
        let extracted = IssueBodyBuilder.extractUserBody(from: assembled)
        XCTAssertEqual(extracted, bodyText)
        XCTAssertFalse(extracted.contains("gittickets-id"))
    }

    // MARK: - AttachmentNameDisplay
    //
    // Scope note that applies to every test below: this option governs
    // SDK-INJECTED attachment metadata only. Text the user typed into their own
    // description is THEIRS and still appears verbatim — see
    // `test_genericModeLeavesUserTypedFilenameInTheirOwnProseAlone`. Scrubbing
    // the user's own prose is explicitly not attempted.

    /// A sensitive-looking set of attachments, in the adopter's shape: a
    /// document vault filing reports to a PUBLIC repo.
    private var sensitiveAttachments: [UploadedAttachment] {
        [
            UploadedAttachment(
                filename: "Tax Return 2024.png",
                url: URL(string: "https://r2.example.com/blob/9f3a1c")!,
                mimeType: "image/png"
            ),
            UploadedAttachment(
                filename: "Mercy Hospital discharge.pdf",
                url: URL(string: "https://r2.example.com/blob/7b2e40")!,
                mimeType: "application/octet-stream"
            ),
        ]
    }

    func test_defaultModeIsFilenameSoExistingBehaviorIsUnchanged() {
        // Omitting the parameter must render exactly what it renders today.
        let omitted = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: sensitiveAttachments
        )
        let explicit = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: sensitiveAttachments,
            attachmentNames: .filename
        )
        XCTAssertEqual(omitted, explicit)
        XCTAssertEqual(PrivacyPolicy.default.attachmentNames, .filename)
    }

    func test_filenameModeRendersTheRealFilename() {
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: sensitiveAttachments,
            attachmentNames: .filename
        )
        XCTAssertTrue(output.contains("![Tax Return 2024.png](https://r2.example.com/blob/9f3a1c)"))
        XCTAssertTrue(output.contains("[Mercy Hospital discharge.pdf](https://r2.example.com/blob/7b2e40)"))
    }

    /// The adopter's acceptance criterion: with the option on, NO user-supplied
    /// filename appears ANYWHERE in the rendered body.
    func test_genericModeLeaksNoFilenameAnywhereInTheBody() {
        let output = IssueBodyBuilder.build(
            report: makeReport(body: "It fails when I open the document."),
            diagnostics: "OS: macOS 15.0\nApp: 1.2 (44)",
            screenshotURL: URL(string: "https://r2.example.com/blob/aa11bb.png")!,
            attachments: sensitiveAttachments,
            attachmentNames: .generic
        )
        // Whole filenames gone.
        XCTAssertFalse(output.contains("Tax Return 2024.png"))
        XCTAssertFalse(output.contains("Mercy Hospital discharge.pdf"))
        // And no fragment of them survives either — a partial leak is a leak.
        for fragment in ["Tax Return", "Tax", "Mercy", "Hospital", "discharge", ".pdf"] {
            XCTAssertFalse(
                output.contains(fragment),
                "fragment \(fragment) of a user filename leaked into the body"
            )
        }
        // Generic labels present instead.
        XCTAssertTrue(output.contains("![image 1](https://r2.example.com/blob/9f3a1c)"))
        XCTAssertTrue(output.contains("[attachment 2](https://r2.example.com/blob/7b2e40)"))
        // The URLs — which hold the bytes — are untouched by this option.
        XCTAssertTrue(output.contains("https://r2.example.com/blob/9f3a1c"))
        XCTAssertTrue(output.contains("https://r2.example.com/blob/7b2e40"))
    }

    /// ONE shared 1-based index across the whole list, noun chosen per item.
    /// `[png, pdf, jpg]` => "image 1", "attachment 2", "image 3". Numbering must
    /// NOT restart per kind: the Nth link is the Nth attachment, so a maintainer
    /// asking "what's in attachment 2?" means something unambiguous.
    func test_genericModeUsesOneSharedIndexAcrossMixedKinds() {
        let mixed = [
            UploadedAttachment(
                filename: "one.png",
                url: URL(string: "https://x/1")!,
                mimeType: "image/png"
            ),
            UploadedAttachment(
                filename: "two.pdf",
                url: URL(string: "https://x/2")!,
                mimeType: "application/octet-stream"
            ),
            UploadedAttachment(
                filename: "three.jpg",
                url: URL(string: "https://x/3")!,
                mimeType: "image/jpeg"
            ),
        ]
        let output = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: mixed,
            attachmentNames: .generic
        )
        XCTAssertTrue(output.contains("![image 1](https://x/1)"))
        XCTAssertTrue(output.contains("[attachment 2](https://x/2)"))
        XCTAssertTrue(output.contains("![image 3](https://x/3)"))
        // The image noun must not restart at 1 for the second image.
        XCTAssertFalse(output.contains("image 2"), "numbering must not restart per kind")
        XCTAssertFalse(output.contains("attachment 1"), "numbering must not restart per kind")
        // Order in the body matches order in the input list.
        let i1 = output.range(of: "image 1")!.lowerBound
        let a2 = output.range(of: "attachment 2")!.lowerBound
        let i3 = output.range(of: "image 3")!.lowerBound
        XCTAssertTrue(i1 < a2 && a2 < i3, "rendered order must track the attachment array order")
    }

    /// The dedicated screenshot path already emits `![screenshot](url)` with no
    /// filename. It is a stated non-goal to change it — assert byte-for-byte
    /// that neither mode alters that line.
    func test_screenshotLineIsIdenticalInBothModes() {
        let shot = URL(string: "https://r2.example.com/blob/shot.png")!
        func body(_ mode: AttachmentNameDisplay) -> String {
            IssueBodyBuilder.build(
                report: makeReport(),
                diagnostics: nil,
                screenshotURL: shot,
                attachments: sensitiveAttachments,
                attachmentNames: mode
            )
        }
        let expected = "![screenshot](https://r2.example.com/blob/shot.png)"
        XCTAssertTrue(body(.filename).contains(expected))
        XCTAssertTrue(body(.generic).contains(expected))
        // And it is not renumbered into the shared attachment index.
        XCTAssertFalse(body(.generic).contains("![image 0]"))
        XCTAssertTrue(body(.generic).contains("![image 1](https://r2.example.com/blob/9f3a1c)"))
    }

    /// A filename stuffed with markdown metacharacters — brackets, parens,
    /// backticks, newlines — must not break out of the link text in EITHER
    /// mode. `.generic` makes it structurally impossible (the name never
    /// reaches the body); `.filename` must still be escaped.
    func test_adversarialFilenameCannotBreakOutOfLinkTextInEitherMode() {
        let hostile = "ev]il[(name)`code`\n\n# Injected Heading\n![x](http://evil/x.png)"
        let attachments = [
            UploadedAttachment(
                filename: hostile,
                url: URL(string: "https://x/blob.png")!,
                mimeType: "image/png"
            )
        ]
        let marker = CorrelationMarker.render(for: fixedID)

        // .generic — the hostile name never reaches the body at all.
        let generic = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: attachments,
            attachmentNames: .generic
        )
        XCTAssertTrue(generic.contains("![image 1](https://x/blob.png)"))
        XCTAssertFalse(generic.contains("Injected Heading"))
        XCTAssertFalse(generic.contains("http://evil/x.png"))
        XCTAssertFalse(generic.contains("`code`"))
        XCTAssertTrue(generic.hasSuffix(marker))

        // .filename — the name is rendered, but escaped and single-line so it
        // stays inside the brackets.
        let named = IssueBodyBuilder.build(
            report: makeReport(),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: attachments,
            attachmentNames: .filename
        )
        // Brackets neutralized, so they can't close the link text early.
        XCTAssertFalse(named.contains("ev]il"), "raw `]` would close the link text")
        XCTAssertTrue(named.contains("ev\\]il\\["))

        // The whole link must live on ONE line. A paragraph break inside the
        // display text would end the link and spill `](url)` into prose, and
        // would let the injected `# Heading` render as a real heading.
        let lines = named.components(separatedBy: "\n")
        let linkLines = lines.filter { $0.contains("](https://x/blob.png)") }
        XCTAssertEqual(linkLines.count, 1, "the attachment link must be exactly one line")
        let linkLine = linkLines[0]
        XCTAssertTrue(linkLine.hasPrefix("!["), "line must begin the image link")
        XCTAssertTrue(linkLine.hasSuffix("](https://x/blob.png)"), "link must close on the same line")

        // No line anywhere in the body may have become a heading or a stray
        // image from the injected payload.
        for line in lines {
            XCTAssertFalse(
                line.hasPrefix("# ") || line.hasPrefix("## "),
                "injected text must not start a line as a heading: \(line)"
            )
        }
        // The injected `![x](http://evil/x.png)` payload is still present as
        // TEXT in this mode — that is expected, the filename is being shown.
        // What matters is that it is inert: its brackets are escaped, so GFM
        // renders it as literal characters rather than a second active image.
        XCTAssertFalse(named.contains("![x]("), "injected image markup must be escaped, not active")
        XCTAssertTrue(named.contains("!\\[x\\]("), "injected brackets should be backslash-escaped")

        // The marker still anchors the end of the body.
        XCTAssertTrue(named.hasSuffix(marker))
    }

    /// Scope clarification the adopter asked us to honor: this option governs
    /// SDK-injected attachment metadata ONLY. A filename the USER typed into
    /// their own description is their own prose and is left alone — rewriting it
    /// would be both wrong and impossible to do safely.
    func test_genericModeLeavesUserTypedFilenameInTheirOwnProseAlone() {
        let typed = "Crashes every time I open Tax Return 2024.png from the vault."
        let output = IssueBodyBuilder.build(
            report: makeReport(body: typed),
            diagnostics: nil,
            screenshotURL: nil,
            attachments: sensitiveAttachments,
            attachmentNames: .generic
        )
        // The user's sentence survives verbatim.
        XCTAssertTrue(output.contains(typed))
        // But the SDK-injected link text is still generic.
        XCTAssertTrue(output.contains("![image 1](https://r2.example.com/blob/9f3a1c)"))
        XCTAssertFalse(output.contains("![Tax Return 2024.png]"))
    }

    /// Empty attachment list must not emit the section in either mode.
    func test_noAttachmentsSectionInEitherModeWhenListIsEmpty() {
        for mode in [AttachmentNameDisplay.filename, .generic] {
            let output = IssueBodyBuilder.build(
                report: makeReport(),
                diagnostics: nil,
                screenshotURL: nil,
                attachments: [],
                attachmentNames: mode
            )
            XCTAssertFalse(output.contains("### Attachments"))
            XCTAssertFalse(output.contains("image 1"))
        }
    }

    /// SOURCE COMPATIBILITY (hard release requirement): the pre-v2.1.0
    /// initializer must keep compiling untouched, and the new parameter must be
    /// defaulted and last. This test failing to COMPILE is the real assertion.
    func test_privacyPolicySourceCompatibility() {
        _ = PrivacyPolicy()
        _ = PrivacyPolicy(bannerText: "Custom.")
        _ = PrivacyPolicy(requireExplicitConsent: false)
        let old = PrivacyPolicy(bannerText: "Custom.", requireExplicitConsent: false)
        XCTAssertEqual(old.attachmentNames, .filename, "old call sites must keep old behavior")

        let new = PrivacyPolicy(
            bannerText: "Custom.",
            requireExplicitConsent: false,
            attachmentNames: .generic
        )
        XCTAssertEqual(new.attachmentNames, .generic)
        XCTAssertEqual(new.bannerText, "Custom.")
        XCTAssertFalse(new.requireExplicitConsent)
    }
}
