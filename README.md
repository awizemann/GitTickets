# GitTickets

A drop-in Swift package (macOS 14+ / iOS 18+) that gives any app a "Report an Issue / Feature Request" surface backed by the app's own GitHub repository.

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

GitHub has no anonymous write surface — every issue, comment, or attachment needs an authenticated request. We refuse to ship a token in the app binary (extractable, breaks every shipped build on rotation). The relay is a small self-contained TypeScript service that holds a GitHub App installation token scoped to `Issues: write` on exactly one repo. You deploy a template and set environment variables — there is no relay code for you to write. Deploy it once, point GitTickets at it, anyone can submit without a GitHub account.

If your users *do* have GitHub accounts (developer tool, internal app), use `.deviceFlow(clientID:)` instead — no relay needed.

## What ships

- Native SwiftUI form + AppKit `NSMenuItem` factory + UIKit container.
- Built-in screenshot capture, diagnostics blob, privacy banner.
- Email / IP / bearer-token redaction by default; custom redactors supported.
- "My Reports" view with developer reply threads.
- Vercel and Cloudflare Worker relay templates in [`/relay/`](relay/).
- Privacy manifest (`PrivacyInfo.xcprivacy`) for App Store submission.

## Status

**v2.3.1 is the current release** — a patch. When a user's reports don't come
back, the screen no longer claims to know why: issues are found by label, so one
is absent whether it was **deleted** or merely **lost its label**, and 2.3.0
wrongly told the deleted case "they haven't been lost".

**v2.3.0** closed the silent failure underneath it: "My Reports" could go
permanently empty with no error, because a dropped label made every past report
invisible while the screen said "No reports yet". The SDK compares what it asked
for against what came back, logs the shortfall, and shows a distinct state.
`refreshMyIssuesDetailed()` returns that detail; `refreshMyIssues()` is
unchanged.

**v2.2.0** fixed a macOS gap where an open "My Reports" or Issue Detail window
could not be refreshed at all — there is now a toolbar Refresh control (⌘R), a
re-fetch when the scene becomes active, and a working
`MyIssuesPolicy.pollInterval` (still **off by default**). See
[`CHANGELOG.md`](CHANGELOG.md).

**Runtime floor (what can run it): macOS 14 (Sonoma) / iOS 18.** Unchanged since 2.0.0, which raised it from macOS 13 / iOS 16 — that dropped platform support is why the major version moved. On iOS it drops two releases: **iOS 17 is excluded too.** Apps deploying below macOS 14 or below iOS 18 should pin `1.0.0`. If your dependency uses `upToNextMajorVersion` from 1.x, it will **not** auto-resolve to 2.x; bump the requirement to `from: "2.3.1"` deliberately. An existing `upToNextMajorVersion` pin from 2.x *does* pick up 2.3.1 automatically.

**Toolchain (what builds it):** built and tested locally on Xcode 26.6 / Swift 6.3.3 — `swift build` with 0 warnings, 307/307 tests, clean generic iOS Simulator build. CI runs green on Xcode 26.3 / `macos-15`, testing iOS against a real iOS 18.6 simulator. Older Xcode versions are untested, so no minimum is claimed here; see [`CHANGELOG.md`](CHANGELOG.md) for the full detail, including a correction to v1.1.0's toolchain claim.

The Phase 2 "My Reports" in-app reply view **has shipped** — browse past submissions, read developer replies, and refresh without reopening the window. See [`CHANGELOG.md`](CHANGELOG.md) for what landed in each release and [`TASKS.md`](TASKS.md) for the active board.

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
