// Examples/iOSSampleApp/iOSSampleApp.swift
//
// A complete reference for integrating GitTickets into a SwiftUI iOS app.
//
// Drop this file into a new SwiftUI iOS App project, add the GitTickets
// package as a dependency (File ▸ Add Package Dependencies… ▸ paste
// https://github.com/<owner>/GitTickets), then replace placeholders below.
//
// iOS hosts present the form as a sheet — the most common pattern. The form
// reads its own "Cancel" button through `@Environment(\.dismiss)`, which
// works with `.sheet(isPresented:)` automatically.

import SwiftUI
import GitTickets

@main
struct iOSSampleApp: App {

    init() {
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
    }
}

struct ContentView: View {

    @State private var showingReport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("iOSSampleApp")
                    .font(.title)
                Text("Tap \"Report an Issue\u{2026}\" below to file a bug.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Report an Issue\u{2026}") {
                    showingReport = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Sample App")
            .sheet(isPresented: $showingReport) {
                // The form is responsible for its own Cancel button (which
                // calls `dismiss()`) and its own Submit, so the host doesn't
                // need to add navigation chrome around it.
                GitTicketsView()
            }
        }
    }
}
