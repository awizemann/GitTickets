import XCTest
import SwiftUI
@testable import GitTickets

@available(macOS 13.0, iOS 16.0, *)
final class GitTicketsCommandsTests: XCTestCase {

    /// Smoke test: the Commands body must build without crashing through both
    /// branches (with and without a keyboard shortcut). SwiftUI's Commands
    /// don't expose their inner buttons for direct assertion, so this is the
    /// minimum guarantee — broken builders (e.g. accidentally using
    /// `CommandMenu` where `CommandGroup` is required) would crash here.
    func test_commandsBuildWithoutShortcut() {
        let commands = GitTicketsCommands(action: {})
        _ = commands.body
    }

    func test_commandsBuildWithShortcut() {
        let commands = GitTicketsCommands(
            title: "Report\u{2026}",
            keyboardShortcut: KeyboardShortcut("r", modifiers: [.command, .shift]),
            action: {}
        )
        _ = commands.body
    }

    /// Spec lock: the public init must accept just an action. Hosts using
    /// defaults shouldn't have to type out the title or shortcut.
    func test_defaultInitAcceptsActionOnly() {
        let commands = GitTicketsCommands { /* no-op */ }
        XCTAssertEqual(commands.title, "Report an Issue\u{2026}")
        XCTAssertNil(commands.keyboardShortcut)
        XCTAssertFalse(commands.isDisabled)
    }

    /// Memophant lands the menu in the app menu (`.appInfo`) instead of Help.
    /// `CommandGroupPlacement` isn't `Equatable`, so we can't compare values
    /// directly — but we can confirm `body` builds against the non-default
    /// placement, which is what would break if `CommandGroup(after: placement)`
    /// stopped accepting a stored value.
    func test_placementParameterBuildsBodyForAppInfo() {
        let commands = GitTicketsCommands(placement: .appInfo) {}
        _ = commands.body
    }

    func test_placementParameterBuildsBodyForNewItem() {
        let commands = GitTicketsCommands(placement: .newItem) {}
        _ = commands.body
    }

    func test_isDisabledRoundTripsAndBuildsBody() {
        let commands = GitTicketsCommands(isDisabled: true) {}
        XCTAssertTrue(commands.isDisabled)
        _ = commands.body
    }

    /// The action closure is stored verbatim — invoking it fires the host's
    /// callback. (We can't simulate a real menu click in a unit test, but we
    /// can verify the closure round-trips through the struct's storage.)
    func test_actionClosureRoundTrips() {
        var fired = 0
        let commands = GitTicketsCommands { fired += 1 }
        commands.action()
        commands.action()
        XCTAssertEqual(fired, 2)
    }
}
