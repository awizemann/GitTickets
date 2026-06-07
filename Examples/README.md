# GitTickets Examples

Reference integrations for the three common host shapes. Each `.swift` file
is a complete, copy-paste-ready starting point — adopters create a fresh
Xcode project, drop in the relevant file, add the `GitTickets` package as a
dependency, and replace the placeholders (relay URL, shared secret, repo
coordinates).

| Directory                            | Host shape                          | Wires                                                                     |
| ------------------------------------ | ----------------------------------- | ------------------------------------------------------------------------- |
| [MacSampleApp/](MacSampleApp/)       | SwiftUI macOS app                   | `GitTicketsCommands` + a `Window` scene hosting `GitTicketsView`          |
| [iOSSampleApp/](iOSSampleApp/)       | SwiftUI iOS app                     | `.sheet(isPresented:)` presenting `GitTicketsView`                        |
| [AppKitSampleApp/](AppKitSampleApp/) | Pure AppKit macOS app (no SwiftUI)  | `GitTicketsMenuItemFactory` + `ReportWindowController.shared`             |

These intentionally don't ship as standalone Xcode projects — the file
formats are fragile across Xcode versions and the integration code itself
is short enough that a working sample lives more cleanly as a single
`.swift` reference. See [`docs/getting-started.md`](../docs/getting-started.md)
for the step-by-step walkthrough.

## What the placeholders mean

Every example has three values that must be filled in before it'll run:

- **Relay URL** — the deployed URL of your Vercel or Cloudflare Worker
  relay. See [`docs/relay-deployment.md`](../docs/relay-deployment.md).
- **Shared secret (hex)** — the HMAC secret you configured the relay with
  (`GITTICKETS_SHARED_SECRET`). Use `openssl rand -hex 32` to generate, then
  set both sides to the same value.
- **Repo coordinates** — the `owner/name` pair issues will be filed under,
  plus whether the repo is `.public` (world-readable on github.com) or
  `.private` (visible only to maintainers) — drives the privacy banner copy.

Once those three are in, build + run and pick "Report an Issue\u{2026}" from
the menu (Mac, AppKit) or tap the button (iOS) to file a real issue.
