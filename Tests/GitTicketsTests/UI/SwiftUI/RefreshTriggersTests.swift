import SwiftUI
import XCTest
@testable import GitTickets

/// Covers the two pieces of ``RefreshTriggers`` that carry real logic: the
/// scene-activation gate and the polling loop.
///
/// Both are pure units with injected time, so these exercise the actual
/// behavior — how many fetches happen and when — rather than asserting that a
/// modifier was applied. The toolbar control itself is verified against the
/// real shipped view by `Harnesses/RefreshAffordance` (`swift run SDKHarness`),
/// because whether macOS renders a reachable control is a question about
/// AppKit, not about this code.
@MainActor
final class RefreshTriggersTests: XCTestCase {

    // MARK: Scene activation gate

    /// The first `.active` is the view appearing. `.task` has already fetched,
    /// so re-fetching here would double every screen open.
    func test_gateIgnoresInitialActivation() {
        var gate = ScenePhaseRefreshGate()
        XCTAssertFalse(gate.shouldRefresh(on: .active))
    }

    /// Returning to `.active` after leaving is the case the whole feature
    /// exists for: a report filed elsewhere should appear without reopening.
    func test_gateRefreshesOnReactivation() {
        var gate = ScenePhaseRefreshGate()
        _ = gate.shouldRefresh(on: .active)          // initial appearance
        XCTAssertFalse(gate.shouldRefresh(on: .background))
        XCTAssertTrue(gate.shouldRefresh(on: .active))
    }

    /// Every subsequent round trip refreshes too — the gate must not latch
    /// after firing once.
    func test_gateRefreshesOnEveryLaterReactivation() {
        var gate = ScenePhaseRefreshGate()
        _ = gate.shouldRefresh(on: .active)
        var fires = 0
        for _ in 0..<3 {
            _ = gate.shouldRefresh(on: .inactive)
            if gate.shouldRefresh(on: .active) { fires += 1 }
        }
        XCTAssertEqual(fires, 3)
    }

    /// Non-active phases never trigger a fetch, including before the first
    /// activation is ever seen.
    func test_gateIgnoresNonActivePhases() {
        var gate = ScenePhaseRefreshGate()
        XCTAssertFalse(gate.shouldRefresh(on: .inactive))
        XCTAssertFalse(gate.shouldRefresh(on: .background))
    }

    // MARK: Polling

    /// `0` is the default and must mean "never poll" — not "poll immediately",
    /// which is what an unguarded `Task.sleep(for: .seconds(0))` loop would do
    /// and would hammer the relay.
    func test_pollingDisabledAtZeroNeverSleepsOrFires() async {
        var sleeps: [TimeInterval] = []
        var fires = 0
        await RefreshPolling.run(
            interval: 0,
            sleep: { sleeps.append($0) },
            isCancelled: { false },
            action: { fires += 1 }
        )
        XCTAssertEqual(sleeps, [])
        XCTAssertEqual(fires, 0)
    }

    /// A negative interval is nonsense input and must behave like `0` rather
    /// than spinning.
    func test_pollingDisabledForNegativeInterval() async {
        var fires = 0
        await RefreshPolling.run(
            interval: -5,
            sleep: { _ in },
            isCancelled: { false },
            action: { fires += 1 }
        )
        XCTAssertEqual(fires, 0)
    }

    /// The loop sleeps the configured interval and fires once per pass.
    func test_pollingSleepsConfiguredIntervalAndFiresEachPass() async {
        var sleeps: [TimeInterval] = []
        var fires = 0
        // Cancel after three passes so the loop terminates.
        await RefreshPolling.run(
            interval: 30,
            sleep: { sleeps.append($0) },
            isCancelled: { fires >= 3 },
            action: { fires += 1 }
        )
        XCTAssertEqual(fires, 3)
        XCTAssertEqual(sleeps, [30, 30, 30])
    }

    /// Cancellation during the sleep must abandon the pass, not fire the action
    /// on the way out — otherwise a dismissed screen still issues a request.
    func test_pollingCancelledDuringSleepDoesNotFire() async {
        struct Cancelled: Error {}
        var fires = 0
        await RefreshPolling.run(
            interval: 30,
            sleep: { _ in throw Cancelled() },
            isCancelled: { false },
            action: { fires += 1 }
        )
        XCTAssertEqual(fires, 0)
    }

    /// Cancellation observed after the sleep also suppresses the fetch.
    func test_pollingCancelledAfterSleepDoesNotFire() async {
        var fires = 0
        var slept = false
        await RefreshPolling.run(
            interval: 30,
            sleep: { _ in slept = true },
            isCancelled: { slept },   // false on entry, true once the sleep ran
            action: { fires += 1 }
        )
        XCTAssertTrue(slept)
        XCTAssertEqual(fires, 0)
    }

    // MARK: Configuration plumbing

    /// `pollInterval` was public but dead before this change; confirm the value
    /// an adopter sets is the one the screens read.
    @MainActor
    func test_configuredPollIntervalReadsActiveConfiguration() {
        let previous = GitTickets.configuration
        defer { if let previous { GitTickets.configure(previous) } }

        GitTickets.configure(
            Configuration(
                repo: RepoCoordinate(owner: "o", name: "n"),
                auth: .mock,
                myIssues: MyIssuesPolicy(pollInterval: 120)
            )
        )
        XCTAssertEqual(configuredPollInterval, 120)
    }

    /// The default stays off, so existing adopters see no new network traffic.
    @MainActor
    func test_defaultPolicyLeavesPollingOff() {
        XCTAssertEqual(MyIssuesPolicy.default.pollInterval, 0)
    }
}
