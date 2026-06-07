#if os(macOS)
import XCTest
import AppKit
@testable import GitTickets

@available(macOS 13.0, *)
final class GitTicketsMenuItemFactoryTests: XCTestCase {

    func test_defaultTitleAndNoShortcut() {
        let item = GitTicketsMenuItemFactory.makeReportIssueItem()
        XCTAssertEqual(item.title, "Report an Issue\u{2026}")
        XCTAssertEqual(item.keyEquivalent, "")
        XCTAssertTrue(item.keyEquivalentModifierMask.isEmpty)
    }

    func test_customTitleAndShortcut() {
        let item = GitTicketsMenuItemFactory.makeReportIssueItem(
            title: "File a bug",
            keyEquivalent: "b",
            keyEquivalentModifierMask: [.command, .shift]
        )
        XCTAssertEqual(item.title, "File a bug")
        XCTAssertEqual(item.keyEquivalent, "b")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .shift])
    }

    /// The action closure must fire when the menu item's selector is invoked.
    /// Documented contract: hosts insert this item into NSMenu and expect
    /// menu-bar clicks to flow through to their closure.
    func test_actionFiresWhenSelectorPerformed() {
        var fired = 0
        let item = GitTicketsMenuItemFactory.makeReportIssueItem(
            action: { fired += 1 }
        )
        // Simulate the menu click by calling the wired action selector
        // against the wired target. `action` is `#selector(MenuActionTarget.fire(_:))`.
        let target = try? XCTUnwrap(item.target)
        let action = try? XCTUnwrap(item.action)
        _ = target?.perform(action, with: item)
        XCTAssertEqual(fired, 1)
    }

    /// Footgun guard: `NSMenuItem.target` is a weak reference. The factory
    /// must retain the trampoline elsewhere (via `representedObject`) or the
    /// trampoline gets deallocated as soon as `makeReportIssueItem` returns
    /// and the action never fires.
    func test_targetIsRetainedAcrossScope() {
        let item: NSMenuItem = {
            return GitTicketsMenuItemFactory.makeReportIssueItem(action: {})
        }()
        // After the inner scope returns, the trampoline must still be alive.
        XCTAssertNotNil(item.target)
        XCTAssertTrue(item.representedObject is MenuActionTarget,
                      "representedObject must hold the action target so it isn't deallocated when NSMenuItem's weak target reference is the only one")
    }
}
#endif
