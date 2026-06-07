// Examples/MacSampleApp/MacSampleApp.swift
//
// A complete reference for integrating GitTickets into a SwiftUI macOS app.
//
// Drop this file into a new SwiftUI macOS App project, add the GitTickets
// package as a dependency (File ▸ Add Package Dependencies… ▸ paste
// https://github.com/<owner>/GitTickets), then replace placeholders below.
//
// The integration is three small pieces:
//
//   1. `GitTickets.configure(...)` at app launch with the relay URL + secret.
//   2. `GitTicketsCommands { ... }` to drop "Report an Issue…" into the menu.
//   3. A `Window(...)` scene that hosts `GitTicketsView()`.

import SwiftUI
import GitTickets

@main
struct MacSampleApp: App {

    init() {
        // Replace with the URL of your deployed relay + the hex shared secret
        // it was configured with (`GITTICKETS_SHARED_SECRET`). See
        // `docs/relay-deployment.md` for the deployment walkthrough.
        guard
            let relayURL = URL(string: "https://your-relay.vercel.app"),
            let secret = SharedSecret(hex: "<your-shared-secret-hex>")
        else {
            preconditionFailure("Replace the relay URL + secret placeholders before running.")
        }

        GitTickets.configure(.init(
            repo: RepoCoordinate(
                owner: "<your-github-org-or-user>",
                name: "<your-repo>",
                visibility: .public
            ),
            auth: .relay(url: relayURL, sharedSecret: secret)
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            // Wraps the package's `GitTicketsCommands` so the action closure
            // can read `@Environment(\.openWindow)` — the package itself is
            // UI-agnostic and doesn't reach into the environment.
            ReportIssueCommands()
        }

        Window("Report an Issue", id: WindowID.report) {
            GitTicketsView()
        }
        .defaultSize(width: 580, height: 720)
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("MacSampleApp")
                .font(.title)
            Text("Press ⌘? then look for \"Report an Issue\u{2026}\" in the Help menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 480, minHeight: 320)
        .padding()
    }
}

/// Stable identifier for the report window, shared between the menu trigger
/// and the `Window` scene declaration.
enum WindowID {
    static let report = "report-issue"
}

/// Wraps the package's `GitTicketsCommands` so the action closure can read
/// `@Environment(\.openWindow)`. Lives in the host because the package
/// commands type takes a closure; the closure has nowhere to source the
/// environment value from without a host-side `Commands` type to read it.
private struct ReportIssueCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        GitTicketsCommands(placement: .help) {
            openWindow(id: WindowID.report)
        }
    }
}
