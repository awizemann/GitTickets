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

    /// How long to wait for SwiftUI to bridge the toolbar onto the hosting
    /// window. Under `swift test` it takes ~0.5s; under `xcodebuild test` it was
    /// measured at ~1.5-2s per window on a dev Mac, and a headless CI runner is
    /// slower still (the old fixed 1s budget returned an empty toolbar there).
    /// The loop exits as soon as the toolbar settles, so a generous ceiling
    /// costs nothing on the happy path.
    private static let toolbarBridgeTimeout: Duration = .seconds(10)
    private static let toolbarPollInterval: Duration = .milliseconds(50)
    /// The view has two independent `.toolbar` sources (the Done/New items and
    /// `refreshTriggers`), which SwiftUI bridges on different run-loop turns —
    /// "Refresh reports" can land before "Done". So readiness is "Refresh
    /// reports is present AND the toolbar has stopped changing for this long".
    private static let toolbarSettleTime: Duration = .milliseconds(500)

    /// Hosts `view` in a window, waits (bounded) until SwiftUI has bridged its
    /// toolbar and it has settled, then returns every label, tooltip, and
    /// menu-form title on the window's toolbar items.
    ///
    /// "Refresh reports" is emitted unconditionally, so once it is present and
    /// the item set is stable, the presence/absence of "Done" is meaningful.
    /// If that never happens within the timeout, this fails loudly naming the
    /// timeout instead of returning a partial set.
    ///
    /// Each window is fully torn down before returning (content controller
    /// released, window closed, run loop drained) so consecutive renders can't
    /// interfere and no windows leak into other tests.
    private func renderedControlTitles(
        _ view: GitTicketsMyIssuesView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> Set<String> {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: view)
        window.makeKeyAndOrderFront(nil)

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Self.toolbarBridgeTimeout)
        var titles: Set<String> = []
        var itemCount = -1
        var lastChange = clock.now
        var ready = false
        // Toolbar bridging happens over several run-loop turns, not
        // synchronously; poll until it lands and settles, or the deadline.
        while true {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let nowTitles = toolbarTitles(in: window)
            let nowCount = window.toolbar?.items.count ?? 0
            if nowTitles != titles || nowCount != itemCount {
                titles = nowTitles
                itemCount = nowCount
                lastChange = clock.now
            }
            if titles.contains("Refresh reports"),
               clock.now - lastChange >= Self.toolbarSettleTime {
                ready = true
                break
            }
            if clock.now >= deadline { break }
            try await Task.sleep(for: Self.toolbarPollInterval)
        }

        await closeHostWindow(window)

        if !ready {
            XCTFail(
                "toolbar was not bridged and settled within \(Self.toolbarBridgeTimeout) "
                    + "(expected a \"Refresh reports\" item, stable for \(Self.toolbarSettleTime)); found \(titles.sorted()), "
                    + "\(itemCount) toolbar item(s)",
                file: file,
                line: line
            )
        }
        return titles
    }

    /// Closes `window` and releases its SwiftUI content, then yields a few
    /// run-loop turns so AppKit/SwiftUI finish their deferred teardown before
    /// the next window is created.
    private func closeHostWindow(_ window: NSWindow) async {
        window.orderOut(nil)
        window.toolbar = nil
        window.contentViewController = nil
        window.close()
        for _ in 0..<3 {
            try? await Task.sleep(for: .milliseconds(10))
        }
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
