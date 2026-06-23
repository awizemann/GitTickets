import XCTest
import SwiftUI
@testable import GitTickets

@available(macOS 13.0, iOS 16.0, *)
@MainActor
final class GitTicketsMyIssuesCommandsTests: XCTestCase {

    func test_defaultsAcceptsActionOnly() {
        let commands = GitTicketsMyIssuesCommands { /* no-op */ }
        XCTAssertEqual(commands.title, "My Reports\u{2026}")
        XCTAssertFalse(commands.isDisabled)
        XCTAssertNil(commands.keyboardShortcut)
    }

    func test_actionClosureRoundTrips() {
        var fired = 0
        let commands = GitTicketsMyIssuesCommands { fired += 1 }
        commands.action()
        commands.action()
        XCTAssertEqual(fired, 2)
    }

    func test_bodyBuildsForAppInfoPlacement() {
        let commands = GitTicketsMyIssuesCommands(placement: .appInfo) {}
        _ = commands.body
    }

    func test_isDisabledRoundTripsAndBuildsBody() {
        let commands = GitTicketsMyIssuesCommands(isDisabled: true) {}
        XCTAssertTrue(commands.isDisabled)
        _ = commands.body
    }
}
