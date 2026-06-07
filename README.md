# GitTickets

A drop-in Swift package (macOS 13+ / iOS 16+) that gives any app a "Report an Issue / Feature Request" surface backed by the app's own GitHub repository.

End-users get a native form, screenshots, diagnostics, and a privacy banner. Submissions land directly as issues in your repo. Users browse their past submissions and see your replies as a thread, inside the app.

Bar: Sparkle-easy to integrate. Add the package, point it at your relay, drop `GitTicketsCommands { … }` into your SwiftUI `Commands` builder.

## 30-second setup

```swift
import GitTickets

@main
struct MyApp: App {
    @State private var showingReport = false

    init() {
        GitTickets.configure(.init(
            repo: .init(owner: "alanw", name: "MyApp", visibility: .public),
            auth: .relay(
                url: URL(string: "https://your-relay.vercel.app")!,
                sharedSecret: SharedSecret(hex: "...")!
            )
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .sheet(isPresented: $showingReport) { GitTicketsView() }
        }
        .commands {
            GitTicketsCommands { showingReport = true }
        }
    }
}
```

The Help menu now contains "Report an Issue…". See [`docs/getting-started.md`](docs/getting-started.md) for the `Window`-scene pattern, the AppKit + UIKit variants, and the per-host sample apps under [`Examples/`](Examples/).

## Why a relay

GitHub has no anonymous write surface — every issue, comment, or attachment needs an authenticated request. We refuse to ship a token in the app binary (extractable, breaks every shipped build on rotation). The relay is ~100 lines of TypeScript that holds a GitHub App installation token scoped to `Issues: write` on exactly one repo. Deploy it once, point GitTickets at it, anyone can submit without a GitHub account.

If your users *do* have GitHub accounts (developer tool, internal app), use `.deviceFlow(clientID:)` instead — no relay needed.

## What ships

- Native SwiftUI form + AppKit `NSMenuItem` factory + UIKit container.
- Built-in screenshot capture, diagnostics blob, privacy banner.
- Email / IP / bearer-token redaction by default; custom redactors supported.
- "My Reports" view with developer reply threads.
- Vercel and Cloudflare Worker relay templates in [`/relay/`](relay/).
- iOS 17+ Privacy Manifest.

## Status

v1.0.0 is shipped. Feature scope is frozen for the 1.x line; the Phase 2 "My Reports" in-app reply view is on the roadmap as a v1.x point release. See [`CHANGELOG.md`](CHANGELOG.md) for what landed and [`TASKS.md`](TASKS.md) for the active board.

## Documentation

The docs that ship with the SDK live under [`docs/`](docs/):

- [Getting started](docs/getting-started.md) — install, configure, wire the UI.
- [Architecture](docs/architecture.md) — client SDK + dual auth, data flow.
- [Threat model](docs/threat-model.md) — what the relay protects against (and doesn't).
- [Relay deployment](docs/relay-deployment.md) — Vercel + Cloudflare walkthrough.
- [Device Flow](docs/device-flow.md) — opt-in OAuth path.
- [Theming](docs/theming.md) — `GitTicketsTheme` fields + examples.
- [Diagnostics](docs/diagnostics.md) — what's collected, redaction, opt-outs.
- [Privacy](docs/privacy.md) — privacy manifest + adopter guidance.

## Design

The default visual look ships as a Claude Design handoff under [`design/design_handoff_gittickets_views_generic/`](design/design_handoff_gittickets_views_generic/). Open `reference/GitTickets Redesign (Generic).html` in a browser to see the macOS + iOS frames the SwiftUI is designed to. The design is theme-agnostic — adopters override the accent via `Configuration.theme` without touching the layout.

## License

MIT. See [LICENSE](LICENSE).

## Security

See [SECURITY.md](SECURITY.md) for disclosure process. SDK and relay templates are both in scope.
