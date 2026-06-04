---
title: Architecture
type: note
permalink: gittickets-wiki/architecture
---

# Architecture

GitTickets is a client Swift package plus an optional developer-deployed serverless relay.

## Why a relay at all

GitHub has **no anonymous write surface**. Every issue, every comment, every attachment requires an authenticated request. Three options exist, and only one fits "my mom can report a bug":

| Approach | Verdict |
| --- | --- |
| Embed a PAT in the app binary | NEVER. Trivially extractable; rotating breaks every shipped build. |
| OAuth Device Flow (end-user signs in to GitHub) | Fine for developer-targeted apps; wrong default for consumer apps because every user needs a GitHub account. |
| GitHub App + tiny developer-hosted relay | Default. Relay holds an installation token scoped to one repo (`Issues: write`). Anyone can submit without a GitHub account. |

GitTickets ships both **relay** (default) and **Device Flow** (opt-in) so adopters pick per app.

## Data flow

```
┌──────────────────────────┐     HMAC-signed POST     ┌───────────────────────┐
│  Host app                │  ─────────────────────▶  │  Relay (Vercel/CF)    │
│  ┌────────────────────┐  │                          │  - Verifies HMAC      │
│  │ GitTickets SDK     │  │  ◀── { issueURL, ... }   │  - Mints App JWT      │
│  │                    │  │                          │  - Stores attachments │
│  │ IssueSubmitter ◀───┼──┤  RelaySubmitter          │  - POSTs to GitHub    │
│  │   protocol         │  │                          │  - Per-IP rate-limits │
│  └────────────────────┘  │                          └──────────┬────────────┘
│           │              │                                     │
│           └──────────────┼──── DeviceFlowSubmitter (opt-in) ──▶│
└──────────────────────────┘     ASWebAuthSession + user token   │
                                                                 ▼
                                                       ┌────────────────────┐
                                                       │   github.com       │
                                                       │   /repos/.../issues│
                                                       │   label: gittickets│
                                                       │   <!-- id: UUID -->│
                                                       └────────────────────┘
```

The UI layer never branches on auth mode — `RelaySubmitter` and `DeviceFlowSubmitter` both conform to an internal `IssueSubmitter` protocol with `submit(_ report: Report) async throws -> SubmittedIssue`.

## Public surface

One entry point:

```swift
GitTickets.configure(.init(
  repo: .init(owner: "alanw", name: "MyApp", visibility: .public),
  auth: .relay(url: URL(string: "https://relay.example.com")!, sharedSecret: .myAppSecret),
  theme: .default,
  diagnostics: .default,
  privacy: .default,
  myIssues: .default
))
```

One menu integration per UI framework:

- SwiftUI: `.commands { GitTicketsCommands() }` — adds "Report an Issue…" and "My Reports…" to the Help menu (macOS) or wires a `.gitTicketsReportButton()` modifier (iOS).
- AppKit: `GitTicketsMenuItemFactory.makeReportIssueItem()` returns an `NSMenuItem` you add wherever you like.
- UIKit: `present(GitTicketsViewController(kind: .bug), animated: true)`.

## Module layout

See [Build Sequence](Build-Sequence) for the PR ordering. The file tree under `Sources/GitTickets/`:

- `PublicAPI/` — `GitTickets.swift`, `Configuration.swift`, `AuthMode.swift`, `Models.swift`, errors, theme.
- `Auth/` — `IssueSubmitter` protocol; `Relay/` (HMAC, payload, client); `DeviceFlow/` (coordinator, token store).
- `Networking/` — `HTTPClient`, `GitHubAPI` for `GET /issues` and `GET /comments`, rate-limit backoff.
- `Storage/` — `SubmissionCache` (SQLite), `DeviceIdentity`, `Keychain` wrapper.
- `Diagnostics/` — collector, blob, redaction pipeline, `OSLogTailer`, `DeviceInfo`.
- `Screenshot/` — platform impls (macOS uses ScreenCaptureKit + CGWindowList fallback; iOS uses `UIGraphicsImageRenderer`).
- `UI/SwiftUI/`, `UI/AppKit/`, `UI/UIKit/` — the three integration paths.
- `Bodybuilder/` — assembles the markdown body, embeds the correlation marker.

## Phase 2 — My Issues

Submission IDs are UUIDs embedded as `<!-- gittickets-id: UUID -->` HTML comments in the issue body. The SDK caches every submitted ID locally (SQLite). `GitTicketsMyIssuesView` queries either:

- **Relay path**: `POST {relayURL}/my-issues` with the local ID list. Relay does `GET /repos/.../issues?labels=gittickets&state=all`, matches embedded UUIDs server-side, returns metadata + comment counts.
- **Device Flow path**: SDK calls `GET /repos/.../issues?creator=@me&labels=gittickets` directly with the user's token (no relay needed; OAuth identity is the filter).

Tapping a row opens `IssueDetailView` which fetches `GET /repos/.../issues/{n}/comments` via the same path and renders each comment with `AttributedString(markdown:)`. Mark-as-read state lives in SQLite.

## Theming

`GitTicketsTheme` (fonts, accent override, corner radius, optional header image) injected via `.environment(\.gitTicketsTheme, .myTheme)`. Defaults inherit the host app's `.accentColor` and system fonts — most apps need no customization.

## What we deliberately don't do

- Don't ship a PAT-in-binary mode. Documented in [Threat Model](Threat-Model).
- Don't auto-capture screenshots. User must tap "Add Screenshot."
- Don't bundle fonts or color assets. Borrowed appearance beats imposed appearance.
- Don't depend on any production Swift package. System frameworks only.
- Don't try to render `.github/ISSUE_TEMPLATE/*.yml` Issue Forms in v1 — that's a v1.1 magic move ([Wiki Footgun](https://example.com/footguns)).

---
_Last updated: 2026-06-04 — initial architecture seed_
