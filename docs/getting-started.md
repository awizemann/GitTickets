# Getting started

This is the shortest path from "I want a Report-an-Issue button in my app"
to "user-typed reports are landing as GitHub issues in my repo."

## 1. Pick an auth mode

| Mode             | Best for                                       | Tradeoffs                                                                 |
| ---------------- | ---------------------------------------------- | ------------------------------------------------------------------------- |
| `.relay`         | Consumer apps (end-users don't have GitHub)   | Need to deploy ~10 lines of relay code on Vercel or Cloudflare Workers.   |
| `.deviceFlow`    | Developer-tools or internal apps               | No relay, but users authenticate with their GitHub account. No image attachments (GitHub has no public attachment API). |

Most apps want `.relay`. See [`relay-deployment.md`](relay-deployment.md) for
the ~5-minute deployment. If you're building a CLI / dev tool, see
[`device-flow.md`](device-flow.md) instead.

## 2. Add the package

In Xcode: **File ▸ Add Package Dependencies…** and paste the package URL.
Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/GitTickets", from: "1.0.0"),
]
```

## 3. Configure at launch

```swift
import GitTickets

@main
struct MyApp: App {
    init() {
        GitTickets.configure(.init(
            repo: RepoCoordinate(owner: "me", name: "MyApp", visibility: .public),
            auth: .relay(
                url: URL(string: "https://my-relay.vercel.app")!,
                sharedSecret: SharedSecret(hex: "<the hex you set on the relay>")!
            )
        ))
    }
    // …
}
```

## 4. Wire the UI

### SwiftUI

```swift
.commands {
    GitTicketsCommands(placement: .help) {
        // Open whatever surface fits your app — a sheet, a Window scene, etc.
        showingReport = true
    }
}
.sheet(isPresented: $showingReport) {
    GitTicketsView()
}
```

See [`Examples/MacSampleApp/`](../Examples/MacSampleApp/) for the full
SwiftUI macOS pattern with `Window(id:)`, or
[`Examples/iOSSampleApp/`](../Examples/iOSSampleApp/) for the sheet
pattern on iOS.

### AppKit

```swift
let item = GitTicketsMenuItemFactory.makeReportIssueItem()
NSApp.helpMenu?.addItem(item)
```

See [`Examples/AppKitSampleApp/`](../Examples/AppKitSampleApp/) for the
full pure-AppKit pattern.

### UIKit

```swift
let nav = UINavigationController(rootViewController: GitTicketsViewController())
present(nav, animated: true)
```

## 5. That's it

Build and run. The Help menu (or sheet button on iOS) now opens the form.
The first submission lands as an issue in your configured repo within a
second or two.

## Where to next

- [`relay-deployment.md`](relay-deployment.md) — deploy the relay if you
  haven't yet.
- [`theming.md`](theming.md) — match the form to your app's look.
- [`diagnostics.md`](diagnostics.md) — control what's collected and how
  it's redacted.
- [`privacy.md`](privacy.md) — what the SDK declares to App Store review.
- [`architecture.md`](architecture.md) — the data flow end-to-end.
