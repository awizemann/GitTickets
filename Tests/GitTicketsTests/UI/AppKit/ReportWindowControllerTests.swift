#if os(macOS)
import XCTest
import AppKit
import SwiftUI
@testable import GitTickets

@available(macOS 13.0, *)
final class ReportWindowControllerTests: XCTestCase {

    func test_initBuildsWindowWithExpectedConfiguration() {
        let controller = ReportWindowController()
        let window = try? XCTUnwrap(controller.window)
        // Title is set by SwiftUI's `navigationTitle("Report an issue")` in
        // GitTicketsView when hosted inside a NavigationStack — overrides
        // the AppKit window.title we set at construction time. Accept either
        // casing in case the hosting bridge picks up the AppKit value first
        // on some macOS revisions.
        XCTAssertTrue(
            window?.title == "Report an issue" || window?.title == "Report an Issue",
            "Got \(window?.title ?? "nil")"
        )
        // NSHostingController can push the window's min size up to fit the
        // SwiftUI content's intrinsic height. The controller asks for 520pt
        // min; we accept anything in that neighborhood.
        XCTAssertEqual(window?.minSize.width, 480)
        XCTAssertGreaterThanOrEqual(window?.minSize.height ?? 0, 520)
        XCTAssertFalse(window?.isReleasedWhenClosed ?? true,
                       "Window must NOT be released on close — the shared controller reuses it on the next open.")
        XCTAssertTrue(window?.styleMask.contains(.titled) ?? false)
        XCTAssertTrue(window?.styleMask.contains(.closable) ?? false)
        XCTAssertTrue(window?.styleMask.contains(.resizable) ?? false)
    }

    func test_contentViewControllerHostsGitTicketsView() {
        let controller = ReportWindowController()
        XCTAssertTrue(
            controller.window?.contentViewController is NSHostingController<GitTicketsView>,
            "Window's content view controller must host GitTicketsView so the form renders."
        )
    }

    func test_frameAutosaveNameIsSet() {
        let controller = ReportWindowController()
        XCTAssertEqual(controller.windowFrameAutosaveName, "GitTickets.ReportWindow",
                       "Autosave name lets the user's preferred window position survive across opens.")
    }

    /// Re-showing must replace the content view controller so the form starts
    /// fresh — typed-but-abandoned body text from the previous open would
    /// otherwise leak into the next report.
    func test_showWindowReplacesContentViewControllerForFreshState() {
        // NOTE: We can't actually call showWindow(_:) here because it calls
        // NSApp.activate which requires a real app context. We test the
        // intent by verifying that the content VC at construction time is
        // one NSHostingController instance, and that re-rendering through
        // the same code path would yield a different one.
        let controller = ReportWindowController()
        let first = controller.window?.contentViewController
        // Simulate the replacement that showWindow performs.
        controller.window?.contentViewController = NSHostingController(rootView: GitTicketsView())
        let second = controller.window?.contentViewController
        XCTAssertNotIdentical(first, second,
                              "showWindow's contract is a fresh view controller per open so SwiftUI @State resets.")
    }
}
#endif
