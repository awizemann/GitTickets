import XCTest
import SwiftUI
@testable import GitTickets

/// The optional `onClose` affordance on ``GitTicketsMyIssuesView``.
///
/// The "Done" button is only reachable through the toolbar, so these tests
/// drive the two internal seams the body uses: `showsCloseButton` (whether the
/// toolbar item is emitted) and `close()` (the button's action).
@MainActor
final class GitTicketsMyIssuesViewTests: XCTestCase {

    private func emptyLoader() async throws -> [SubmittedIssue] { [] }

    private func emptyDetailedLoader() async throws -> MyIssuesRefresh {
        MyIssuesRefresh(issues: [], requestedCount: 0)
    }

    // MARK: - No close action

    func test_defaultInitWithoutOnCloseShowsNoCloseButton() {
        let view = GitTicketsMyIssuesView()
        XCTAssertFalse(view.showsCloseButton)
        view.close()  // a no-op, must not trap
        _ = view.body
    }

    func test_loadIssuesInitWithoutOnCloseShowsNoCloseButton() {
        let view = GitTicketsMyIssuesView(
            loadIssues: emptyLoader,
            detail: { IssueDetailView(issue: $0) }
        )
        XCTAssertFalse(view.showsCloseButton)
        _ = view.body
    }

    func test_loadDetailedInitWithoutOnCloseShowsNoCloseButton() {
        let view = GitTicketsMyIssuesView(
            loadDetailed: emptyDetailedLoader,
            detail: { IssueDetailView(issue: $0) }
        )
        XCTAssertFalse(view.showsCloseButton)
        _ = view.body
    }

    /// `onNew` alone must not turn on the close button — the two closures are
    /// independent and positional mix-ups would be easy to miss.
    func test_onNewAloneDoesNotShowCloseButton() {
        var newCalls = 0
        let view = GitTicketsMyIssuesView(onNew: { newCalls += 1 })
        XCTAssertFalse(view.showsCloseButton)
        view.close()
        XCTAssertEqual(newCalls, 0)
    }

    // MARK: - With close action

    func test_defaultInitInvokesSuppliedOnClose() {
        var closeCalls = 0
        var newCalls = 0
        let view = GitTicketsMyIssuesView(
            onNew: { newCalls += 1 },
            onClose: { closeCalls += 1 }
        )
        XCTAssertTrue(view.showsCloseButton)
        view.close()
        XCTAssertEqual(closeCalls, 1)
        XCTAssertEqual(newCalls, 0, "close must not route to onNew")
        _ = view.body
    }

    func test_defaultInitAcceptsOnCloseWithoutOnNew() {
        var closeCalls = 0
        let view = GitTicketsMyIssuesView(onClose: { closeCalls += 1 })
        XCTAssertTrue(view.showsCloseButton)
        view.close()
        view.close()
        XCTAssertEqual(closeCalls, 2)
    }

    func test_loadIssuesInitInvokesSuppliedOnClose() {
        var closeCalls = 0
        var newCalls = 0
        let view = GitTicketsMyIssuesView(
            loadIssues: emptyLoader,
            onNew: { newCalls += 1 },
            onClose: { closeCalls += 1 },
            detail: { IssueDetailView(issue: $0) }
        )
        XCTAssertTrue(view.showsCloseButton)
        view.close()
        XCTAssertEqual(closeCalls, 1)
        XCTAssertEqual(newCalls, 0)
        _ = view.body
    }

    func test_loadDetailedInitInvokesSuppliedOnClose() {
        var closeCalls = 0
        let view = GitTicketsMyIssuesView(
            loadDetailed: emptyDetailedLoader,
            onClose: { closeCalls += 1 },
            detail: { IssueDetailView(issue: $0) }
        )
        XCTAssertTrue(view.showsCloseButton)
        view.close()
        XCTAssertEqual(closeCalls, 1)
        _ = view.body
    }

    // MARK: - Hosted (macOS)

    #if os(macOS)
    /// The plumbing tests above would still pass if the `ToolbarItem` were
    /// deleted. This hosts the real view in a window and inspects the
    /// `NSToolbar` SwiftUI bridges onto it, like the RefreshAffordance harness.
    ///
    /// In a headless XCTest process the toolbar never lays its items out (they
    /// sit in the overflow with zero frames), so their SwiftUI content exposes
    /// no titles or accessibility labels. What SwiftUI DOES populate on each
    /// `NSToolbarItem` is metadata: a text button's title becomes the item's
    /// `menuFormRepresentation` title ("Done"), and `.help` becomes its
    /// `toolTip` ("Refresh reports"). The test reads those.
    func test_hostedDoneButtonAppearsOnlyWithOnClose() async throws {
        let withClose = try await renderedControlTitles(
            GitTicketsMyIssuesView(loadDetailed: emptyDetailedLoader, onClose: {}, detail: { IssueDetailView(issue: $0) })
        )
        XCTAssertTrue(withClose.contains("Done"), "no Done control rendered; found \(withClose)")

        let withoutClose = try await renderedControlTitles(
            GitTicketsMyIssuesView(loadDetailed: emptyDetailedLoader, detail: { IssueDetailView(issue: $0) })
        )
        XCTAssertFalse(withoutClose.contains("Done"), "unexpected Done control; found \(withoutClose)")
        // Sanity: the hosted toolbar really is rendering, so the absence above
        // is meaningful rather than "nothing rendered at all".
        XCTAssertTrue(
            withoutClose.contains("Refresh reports"),
            "toolbar did not render at all; found \(withoutClose)"
        )
    }

    /// Hosts `view` in a window, lets SwiftUI bridge its toolbar, then returns
    /// every label, tooltip, and menu-form title on the window's toolbar items.
    private func renderedControlTitles(_ view: GitTicketsMyIssuesView) async throws -> Set<String> {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        // Toolbar bridging happens over a few runloop turns, not synchronously.
        var titles: Set<String> = []
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(50))
            window.contentView?.layoutSubtreeIfNeeded()
            titles = toolbarTitles(in: window)
            if titles.contains("Refresh reports") { break }
        }
        return titles
    }

    private func toolbarTitles(in window: NSWindow) -> Set<String> {
        var out: Set<String> = []
        for item in window.toolbar?.items ?? [] {
            for s in [item.label, item.paletteLabel, item.toolTip, item.menuFormRepresentation?.title] {
                if let s, !s.isEmpty { out.insert(s) }
            }
        }
        return out
    }
    #endif
}
