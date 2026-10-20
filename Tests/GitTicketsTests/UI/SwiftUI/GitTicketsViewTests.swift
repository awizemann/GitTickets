import XCTest
import SwiftUI
@testable import GitTickets

@MainActor
final class GitTicketsViewTests: XCTestCase {

    // MARK: - PrivacyBanner copy

    func test_privacyBannerPublicCopy() {
        let copy = PrivacyBanner.copy(
            repo: RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: .public),
            policy: .default
        )
        XCTAssertEqual(copy, "This will be posted publicly to github.com/alanw/GitTickets.")
    }

    func test_privacyBannerPrivateCopy() {
        let copy = PrivacyBanner.copy(
            repo: RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: .private),
            policy: .default
        )
        XCTAssertEqual(copy, "This will be visible to repo maintainers at github.com/alanw/GitTickets.")
    }

    func test_privacyBannerOverrideWinsOverVisibilityDefault() {
        let copy = PrivacyBanner.copy(
            repo: RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: .public),
            policy: PrivacyPolicy(bannerText: "Custom warning.", requireExplicitConsent: true)
        )
        XCTAssertEqual(copy, "Custom warning.")
    }

    func test_privacyBannerEmptyOverrideFallsBackToVisibilityCopy() {
        // An empty override string should NOT silently swallow the default —
        // adopters who null-out the banner are almost always asking to keep
        // the default, not to ship an empty info chip.
        let copy = PrivacyBanner.copy(
            repo: RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: .public),
            policy: PrivacyPolicy(bannerText: "", requireExplicitConsent: true)
        )
        XCTAssertEqual(copy, "This will be posted publicly to github.com/alanw/GitTickets.")
    }

    // MARK: - mimeType

    func test_mimeTypeForKnownExtensions() {
        XCTAssertEqual(GitTicketsView.mimeType(for: URL(fileURLWithPath: "shot.png")), "image/png")
        XCTAssertEqual(GitTicketsView.mimeType(for: URL(fileURLWithPath: "shot.jpg")), "image/jpeg")
        XCTAssertEqual(GitTicketsView.mimeType(for: URL(fileURLWithPath: "shot.jpeg")), "image/jpeg")
        XCTAssertEqual(GitTicketsView.mimeType(for: URL(fileURLWithPath: "shot.heic")), "image/heic")
        XCTAssertEqual(GitTicketsView.mimeType(for: URL(fileURLWithPath: "shot.gif")), "image/gif")
        XCTAssertEqual(GitTicketsView.mimeType(for: URL(fileURLWithPath: "shot.webp")), "image/webp")
    }

    func test_mimeTypeFallsBackToOctetStreamForUnknown() {
        XCTAssertEqual(GitTicketsView.mimeType(for: URL(fileURLWithPath: "report.xyz")), "application/octet-stream")
    }

    // MARK: - ScreenshotThumbnail.makeImage

    func test_screenshotThumbnailReturnsNilForGarbageBytes() {
        XCTAssertNil(ScreenshotThumbnail.makeImage(from: Data([0x00, 0x01, 0x02])))
    }

    func test_screenshotThumbnailDecodesPNGMagicBytes() throws {
        // Smallest valid 1x1 PNG, base64'd from the canonical test fixture so
        // we don't pull a binary into the repo.
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        XCTAssertNotNil(ScreenshotThumbnail.makeImage(from: data))
    }

    // MARK: - Initializer plumbing

    /// Confirms the configuration-injected init builds without crashing.
    /// Uses `.mock` auth so the submit closure is never reached during view
    /// body evaluation.
    func test_configuredInitBuildsBody() {
        let view = GitTicketsView(
            configuration: Configuration(
                repo: RepoCoordinate(owner: "alanw", name: "GitTickets"),
                auth: .mock
            )
        )
        _ = view.body
    }

    // MARK: - Consent copy

    func test_consentMessageDefaultNamesRepo() {
        XCTAssertEqual(
            GitTicketsView.consentMessage(override: nil, isPublic: true, repoSlug: "scarfco/ScarfRack"),
            "I understand this report and the diagnostics above will be posted publicly to scarfco/ScarfRack."
        )
        XCTAssertEqual(
            GitTicketsView.consentMessage(override: nil, isPublic: false, repoSlug: "scarfco/ScarfRack"),
            "I understand this report and the diagnostics above will be posted to scarfco/ScarfRack."
        )
    }

    func test_consentMessageOverrideReplacesRepoCoordinate() {
        let message = GitTicketsView.consentMessage(
            override: "I understand Loom's team will read this.",
            isPublic: false,
            repoSlug: "scarfco/ScarfRack"
        )
        XCTAssertEqual(message, "I understand Loom's team will read this.")
        XCTAssertFalse(message.contains("ScarfRack"))
    }

    func test_consentMessageEmptyOverrideFallsBackToDefault() {
        let message = GitTicketsView.consentMessage(override: "", isPublic: false, repoSlug: "a/b")
        XCTAssertEqual(message, "I understand this report and the diagnostics above will be posted to a/b.")
    }

    func test_privacyPolicyConsentTextDefaultsToNil() {
        XCTAssertNil(PrivacyPolicy.default.consentText)
        XCTAssertEqual(PrivacyPolicy(consentText: "x").consentText, "x")
    }

    // MARK: - Prefill diagnostics

    func test_hostDiagnosticsAreRedactedWithThePolicy() throws {
        let redactor = DiagnosticsRedactor(
            name: "run",
            regex: try NSRegularExpression(pattern: "secret-[0-9]+"),
            replacement: "<redacted>"
        )
        let text = GitTicketsView.redactedHostDiagnostics(
            "  run: secret-42\n",
            policy: DiagnosticsPolicy(redactors: [redactor])
        )
        XCTAssertEqual(text, "run: <redacted>")
    }

    func test_blankHostDiagnosticsCountAsNone() {
        XCTAssertNil(GitTicketsView.redactedHostDiagnostics(nil, policy: .default))
        XCTAssertNil(GitTicketsView.redactedHostDiagnostics(" \n ", policy: .default))
    }

    func test_combinedDiagnosticsKeepsOrderAndDropsRemovedParts() {
        XCTAssertEqual(GitTicketsView.combinedDiagnostics(collected: "OS: 26", host: "run: 1"), "OS: 26\n\nrun: 1")
        XCTAssertEqual(GitTicketsView.combinedDiagnostics(collected: "OS: 26", host: nil), "OS: 26")
        XCTAssertEqual(GitTicketsView.combinedDiagnostics(collected: nil, host: "run: 1"), "run: 1")
        XCTAssertNil(GitTicketsView.combinedDiagnostics(collected: "", host: nil))
    }

    func test_prefilledInitBuildsBody() {
        let view = GitTicketsView(
            configuration: Configuration(
                repo: RepoCoordinate(owner: "alanw", name: "GitTickets"),
                auth: .mock
            ),
            prefill: TicketPrefill(title: "T", body: "B", diagnostics: "run: 1", kind: .featureRequest),
            showsToolbarCancel: false
        )
        _ = view.body
    }

    // MARK: - Hosted toolbar Cancel (macOS)

    #if os(macOS)
    /// Hosts the real form and reads the NSToolbar SwiftUI bridges onto the
    /// window — see GitTicketsMyIssuesViewTests for why it reads menu-form
    /// titles. The default case must show Cancel, which also proves the
    /// toolbar renders, so its absence in the opt-out case means something.
    func test_hostedToolbarCancelCanBeHidden() async throws {
        // LOCAL-ONLY for the same reason as the My Reports Done-button test:
        // the toolbar bridge this reads differs on the CI runner's Xcode.
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("Hosted toolbar inspection is local-only.")
        }
        let config = Configuration(repo: RepoCoordinate(owner: "a", name: "b"), auth: .mock)

        let shown = await toolbarTitles(GitTicketsView(configuration: config), until: { $0.contains("Cancel") })
        XCTAssertTrue(shown.contains("Cancel"), "default form has no toolbar Cancel; found \(shown)")

        let hidden = await toolbarTitles(
            GitTicketsView(configuration: config, showsToolbarCancel: false),
            until: { _ in false }
        )
        XCTAssertFalse(hidden.contains("Cancel"), "toolbar Cancel shown despite opt-out; found \(hidden)")
    }

    /// Polls the hosted window's toolbar until `until` holds or the budget
    /// runs out (the opt-out case waits the full budget on purpose).
    private func toolbarTitles(
        _ view: GitTicketsView,
        until done: (Set<String>) -> Bool,
        budget: Duration = .seconds(3)
    ) async -> Set<String> {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.makeKeyAndOrderFront(nil)

        let deadline = ContinuousClock.now.advanced(by: budget)
        var titles: Set<String> = []
        while ContinuousClock.now < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            titles = []
            for item in window.toolbar?.items ?? [] {
                for s in [item.label, item.paletteLabel, item.toolTip, item.menuFormRepresentation?.title] {
                    if let s, !s.isEmpty { titles.insert(s) }
                }
            }
            if done(titles) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        window.orderOut(nil)
        window.toolbar = nil
        window.contentViewController = nil
        window.close()
        for _ in 0..<3 { try? await Task.sleep(for: .milliseconds(10)) }
        return titles
    }
    #endif
}
