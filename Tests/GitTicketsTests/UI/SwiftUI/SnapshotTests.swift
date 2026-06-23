#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import SnapshotTesting
@testable import GitTickets

/// Snapshot tests for stable, deterministic subviews. macOS-only — iOS Sim
/// snapshot testing requires a host app for layout sizing and would couple us
/// to a specific Simulator runtime version. macOS gives us a single rendering
/// substrate that's enough to catch visual regressions in the layout the
/// theme drives.
///
/// First run records the baseline images under `__Snapshots__/SnapshotTests/`.
/// Subsequent runs compare. Re-record after intentional layout changes with
/// `SNAPSHOT_TESTING_RECORD=1 swift test --filter SnapshotTests`.
@available(macOS 13.0, *)
@MainActor
final class SnapshotTests: XCTestCase {

    private let publicRepo = RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: .public)
    private let privateRepo = RepoCoordinate(owner: "alanw", name: "InternalTool", visibility: .private)

    /// Wraps a SwiftUI view in an `NSHostingController` and pins it to an
    /// explicit size so the `swift-snapshot-testing` `.image` strategy can
    /// render it. Without the explicit frame the hosting controller's view
    /// reports zero size and the snapshot strategy crashes.
    ///
    /// `appearance` overrides the controller's view appearance — required
    /// because `.preferredColorScheme(.dark)` doesn't propagate to the host
    /// view's `NSAppearance` in the test runner's context.
    private func host(
        _ view: some View,
        size: NSSize = NSSize(width: 480, height: 120),
        appearance: NSAppearance.Name = .aqua
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(rootView: AnyView(view.frame(width: size.width, height: size.height)))
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    // MARK: - PrivacyBanner

    func test_privacyBannerPublicLight() {
        let view = PrivacyBanner(repo: publicRepo)
            .frame(width: 480)
            .padding()
            .background(Color.white)
        assertSnapshot(of: host(view), as: .image(precision: 0.99))
    }

    func test_privacyBannerPublicDark() {
        let view = PrivacyBanner(repo: publicRepo)
            .frame(width: 480)
            .padding()
            .background(Color.black)
        assertSnapshot(of: host(view, appearance: .darkAqua), as: .image(precision: 0.99))
    }

    func test_privacyBannerPrivateCopy() {
        let view = PrivacyBanner(repo: privateRepo)
            .frame(width: 480)
            .padding()
            .background(Color.white)
        assertSnapshot(of: host(view), as: .image(precision: 0.99))
    }

    func test_privacyBannerOverrideCopy() {
        let view = PrivacyBanner(
            repo: publicRepo,
            policy: PrivacyPolicy(bannerText: "Custom warning text wins.")
        )
        .frame(width: 480)
        .padding()
        .background(Color.white)
        assertSnapshot(of: host(view), as: .image(precision: 0.99))
    }

    // MARK: - GitTicketsView (redesigned form)

    private var sampleConfiguration: Configuration {
        Configuration(
            repo: RepoCoordinate(owner: "alanw", name: "GitTickets", visibility: .public),
            auth: .mock
        )
    }

    /// Snapshots the new form layout. `.mock` auth keeps it inert — the
    /// submit closure is unreachable from a non-interactive render.
    func test_formLight() {
        let view = GitTicketsView(configuration: sampleConfiguration)
        assertSnapshot(of: host(view, size: NSSize(width: 640, height: 720)), as: .image(precision: 0.99))
    }

    func test_formDark() {
        let view = GitTicketsView(configuration: sampleConfiguration)
        assertSnapshot(
            of: host(view, size: NSSize(width: 640, height: 720), appearance: .darkAqua),
            as: .image(precision: 0.99)
        )
    }
}
#endif
