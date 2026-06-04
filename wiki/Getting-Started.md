---
title: Getting-Started
type: note
permalink: gittickets-wiki/getting-started
---

# Getting Started

The adopter integration walkthrough. Written for a developer who just learned about GitTickets and wants to add it to their SwiftUI macOS app.

> **Status:** Stub. Filled in during PR 17 (Documentation pass). For now, see [Architecture](Architecture) for the public API surface and [Relay Deployment](Relay-Deployment) for the relay setup.

## The 30-second pitch

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

That's it. The Help menu now contains "Report an Issue…" and "My Reports…". Submissions land in `alanw/MyApp` as real GitHub issues.

## Detailed walkthrough

To be written:

1. Install the package.
2. Deploy the relay (link to [Relay Deployment](Relay-Deployment)).
3. Configure the SDK.
4. Add the menu / commands.
5. Theme the form to match your app.
6. (Optional) Enable Device Flow instead of a relay.
7. (Optional) Customize diagnostics.
8. Test the round-trip.

---
_Last updated: 2026-06-04 — stub_
