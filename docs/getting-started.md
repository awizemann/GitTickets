# Getting started

This is the shortest path from "I want a Report-an-Issue button in my app"
to "user-typed reports are landing as GitHub issues in my repo."

> **Requirements — two separate floors.**
>
> - **Runtime floor (what your app can deploy to): macOS 14+ / iOS 18+.** This
>   went up from macOS 13 / iOS 16 in 2.0.0, which is why 2.0.0 is a major
>   version — and on iOS it skips a release, so **iOS 17 is excluded too**. The
>   floor is unchanged in every 2.x release since. Still shipping below macOS 14
>   or below iOS 18? Pin `1.0.0`.
> - **Toolchain (what builds the package):** built and tested on
>   Xcode 26.6 / Swift 6.3.3, and passes CI green on Xcode 26.3. Older Xcode versions
>   are untested, so this doc does not state a minimum one. The manifest is
>   `swift-tools-version:6.0` and declares `.iOS(.v18)`, so a toolchain that
>   cannot parse those cannot resolve the package at all — but that is a
>   manifest constraint, not a tested build.

## 1. Pick an auth mode

| Mode             | Best for                                       | Tradeoffs                                                                 |
| ---------------- | ---------------------------------------------- | ------------------------------------------------------------------------- |
| `.relay`         | Consumer apps (end-users don't have GitHub)   | Need to deploy the relay template on Vercel or Cloudflare Workers. You write no relay code — deploy it and set env vars. |
| `.deviceFlow`    | Developer-tools or internal apps               | No relay, but users authenticate with their GitHub account. No image attachments (GitHub has no public attachment API). |

Most apps want `.relay`. See [`relay-deployment.md`](relay-deployment.md) for
the deployment walkthrough. If you're building a CLI / dev tool, see
[`device-flow.md`](device-flow.md) instead.

## 2. Add the package

In Xcode: **File ▸ Add Package Dependencies…** and paste the package URL.
Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/GitTickets", from: "2.3.0"),
]
```

Already on 1.x? `from: "1.x"` means `upToNextMajorVersion`, which resolves
`[1.0.0, 2.0.0)` and therefore will **not** pick up any 2.x release. Change the
version requirement by hand (here, or on the package reference in Xcode) — and
check your app's deployment target against the macOS 14 / iOS 18 floor first.
An existing pin from any 2.x *does* pick up later 2.x releases automatically.

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

### Keeping the shared secret out of your repo

The literal above lands in git. If your app's repository is public, source
the secret from your `Info.plist` instead and feed that key from a
gitignored `xcconfig`:

```swift
guard let secret = SharedSecret(infoPlistKey: "GitTicketsSharedSecret",
                                encoding: .hex) else {
    // Fail loudly at launch. A missing or malformed secret means every
    // submission will 401, and you want to know now, not from a user.
    fatalError("GitTicketsSharedSecret missing or not valid hex")
}
```

`encoding` is required rather than guessed: a string like `abcdef` is valid
as both hex and base64, and picking wrong would silently derive a different
key and surface as unexplainable `401 signatureMismatch` errors.

**This keeps the secret out of git — it does not keep it out of an
attacker's hands.** `Info.plist` ships as plaintext inside the app bundle
and anyone can read it with `plutil -p MyApp.app/Contents/Info.plist`. The
shared secret gates casual abuse of your relay; it is not protecting
anything, and no client-side storage would change that. See
[`threat-model.md`](threat-model.md).

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

### My Reports

`GitTicketsMyIssuesView()` lists the user's past submissions and the reply
thread on each one. Drop it wherever suits your app — a tab, a window, a sheet.

```swift
GitTicketsMyIssuesView(onNew: { showingReport = true })
```

**Refreshing.** The screen refreshes on first appearance, from a toolbar
Refresh control (⌘R), whenever the scene becomes active again, and — on iOS —
by pull-to-refresh. The toolbar control is the only one a macOS user can reach
directly: `.refreshable` on a `ScrollView` does nothing on macOS.

Optional polling is off by default and generally should stay off — returning to
the window already re-fetches:

```swift
MyIssuesPolicy(pollInterval: 0)   // default; > 0 polls every N seconds
```

Each open screen costs one request per interval against your relay and GitHub's
rate limits.

**When the list comes back empty.** Issues are found by label, so a label that
was never applied — or removed later — makes past reports invisible. Set
`Configuration.logger` and the SDK warns when it asked about cached submissions
and matched none. To handle it yourself:

```swift
let refresh = try await GitTickets.refreshMyIssuesDetailed()
if refresh.allMissing {
    // Cached submissions exist but none came back — a configuration fault,
    // not an empty history. `requestedCount` has the detail.
}
```

`requestedCount == 0` is not a fault: a device that has filed nothing has
nothing to show. See [`relay-deployment.md`](relay-deployment.md) for the fix.

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
