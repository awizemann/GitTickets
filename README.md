# GitTickets

A drop-in Swift package (macOS 13+ / iOS 16+) that gives any app a "Report an Issue / Feature Request" surface backed by the app's own GitHub repository.

End-users get a native form, screenshots, diagnostics, and a privacy banner. Submissions land directly as issues in your repo. Phase 2 (also in v1): users browse their past submissions and see your replies as a thread, inside the app.

Bar: Sparkle-easy to integrate. Add the package, point it at your relay, drop `GitTicketsCommands()` into your SwiftUI `Commands` builder.

## 30-second setup

```swift
import GitTickets

@main
struct MyApp: App {
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
        WindowGroup { ContentView() }
            .commands { GitTicketsCommands() }
    }
}
```

The Help menu now contains "Report an Issue…" and "My Reports…".

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

v1.0 is under active construction. Tracking lives in [`TASKS.md`](TASKS.md). The 20-PR plan is in [`wiki/Build-Sequence.md`](wiki/Build-Sequence.md).

## Documentation

- [Architecture](wiki/Architecture.md) — client SDK + dual auth, data flow.
- [Threat Model](wiki/Threat-Model.md) — what the relay protects against.
- [Relay Deployment](wiki/Relay-Deployment.md) — Vercel + Cloudflare walkthrough.
- [Device Flow](wiki/Device-Flow.md) — opt-in OAuth path.
- [Diagnostics & Screenshots](wiki/Diagnostics-and-Screenshots.md) — what we collect, redaction, capture.

## License

MIT. See [LICENSE](LICENSE).

## Security

See [SECURITY.md](SECURITY.md) for disclosure process. SDK and relay templates are both in scope.
