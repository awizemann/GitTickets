//
//  RefreshTriggers.swift
//  GitTickets — the refresh paths shared by "My Reports" and Issue Detail.
//
//  Why this exists: `.refreshable` is NOT a cross-platform refresh path.
//  Measured against the shipped views on 2026-07-26 (see Harnesses/README.md):
//
//    - iOS: `ScrollView { }.refreshable { }` DOES install a UIRefreshControl.
//      Pull-to-refresh works, so the existing `.refreshable` calls stay.
//    - macOS: the same construction installs nothing at all. The view
//      hierarchy is byte-identical to applying no modifier, and the `refresh`
//      environment action is not even propagated. Only `List` gets an
//      affordance on macOS.
//
//  So on macOS an open window had no way to refresh — closing and reopening it
//  (re-running `.task`) was the only mechanism. The toolbar control below is
//  the fix, and it is the only one of these three triggers a user can reach
//  directly on every platform.
//
//  The two behaviors with real logic — skipping the initial scene activation,
//  and the polling loop — are pure units below so they can be tested without a
//  view hierarchy or a wall-clock wait. The modifier is thin glue over them.
//
//  Deliberately internal: this adds no public API surface to support.
//
//  macOS 14+ / iOS 18+. SwiftUI only.
//

import SwiftUI

// MARK: - Scene activation gate

/// Decides whether a `ScenePhase` change should trigger a re-fetch.
///
/// `scenePhase` reports `.active` on first appearance too, and the owning view's
/// own `.task` has already loaded by then — so the FIRST activation must not
/// cause a second fetch. Every later return to `.active` should.
struct ScenePhaseRefreshGate {

    private var sawInitialActivation = false

    /// - Returns: `true` when this transition should trigger a re-fetch.
    mutating func shouldRefresh(on phase: ScenePhase) -> Bool {
        guard phase == .active else { return false }
        guard sawInitialActivation else {
            sawInitialActivation = true
            return false
        }
        return true
    }
}

// MARK: - Polling

/// The repeating re-fetch driven by ``MyIssuesPolicy/pollInterval``.
///
/// `sleep` and `isCancelled` are injected so the loop is testable without
/// waiting on a real clock.
///
/// Main-actor isolated: every caller drives a SwiftUI reload, and the injected
/// closures capture view state, so hopping off the main actor would only buy
/// `Sendable` friction for work that belongs there anyway.
@MainActor
enum RefreshPolling {

    static func run(
        interval: TimeInterval,
        sleep: (TimeInterval) async throws -> Void,
        isCancelled: () -> Bool,
        action: () async -> Void
    ) async {
        // A non-positive interval disables polling. Guarding here rather than
        // at the call site keeps "0 means off" true for every caller.
        guard interval > 0 else { return }
        while !isCancelled() {
            do {
                try await sleep(interval)
            } catch {
                return  // cancelled mid-sleep
            }
            if isCancelled() { return }
            await action()
        }
    }
}

// MARK: - Modifier

/// Adds the SDK's refresh triggers to a screen: an explicit Refresh control, a
/// re-fetch when the scene becomes active again, and optional polling.
///
/// `.refreshable` is intentionally NOT part of this modifier — it belongs on
/// the specific scroll container, and it only does anything on iOS.
struct RefreshTriggers: ViewModifier {

    @Environment(\.scenePhase) private var scenePhase

    /// Seconds between automatic re-fetches. `0` disables polling entirely.
    let pollInterval: TimeInterval

    /// Localized name for the control, e.g. "Refresh reports".
    let accessibilityLabel: String

    let action: () async -> Void

    @State private var gate = ScenePhaseRefreshGate()

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await action() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(accessibilityLabel)
                    .accessibilityLabel(accessibilityLabel)
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard gate.shouldRefresh(on: phase) else { return }
                Task { await action() }
            }
            .task(id: pollInterval) {
                // `.task(id:)` restarts if the interval changes and cancels on
                // disappear, so the loop needs no manual teardown.
                await RefreshPolling.run(
                    interval: pollInterval,
                    sleep: { try await Task.sleep(for: .seconds($0)) },
                    isCancelled: { Task.isCancelled },
                    action: action
                )
            }
    }
}

extension View {

    /// Wires the Refresh control, scene-reactivation re-fetch, and optional
    /// polling. See ``RefreshTriggers`` for why `.refreshable` alone is not
    /// enough on macOS.
    ///
    /// - Parameters:
    ///   - pollInterval: Seconds between automatic re-fetches; `0` disables it.
    ///   - accessibilityLabel: Name for the control, e.g. `"Refresh reports"`.
    ///   - action: The reload to run.
    func refreshTriggers(
        pollInterval: TimeInterval,
        accessibilityLabel: String,
        action: @escaping () async -> Void
    ) -> some View {
        modifier(
            RefreshTriggers(
                pollInterval: pollInterval,
                accessibilityLabel: accessibilityLabel,
                action: action
            )
        )
    }
}

/// The configured poll interval, or `0` when no configuration is active.
///
/// Mirrors how the views already reach for `GitTickets.configuration?.theme`.
@MainActor
var configuredPollInterval: TimeInterval {
    GitTickets.configuration?.myIssues.pollInterval ?? 0
}
