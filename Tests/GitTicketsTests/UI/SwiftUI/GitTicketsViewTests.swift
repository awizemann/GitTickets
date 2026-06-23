import XCTest
import SwiftUI
@testable import GitTickets

@available(macOS 13.0, iOS 16.0, *)
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
}
