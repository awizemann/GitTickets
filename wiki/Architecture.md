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

- SwiftUI: `.commands { GitTicketsCommands { showingReport = true } }` — drops "Report an Issue…" into the Help menu (or whichever `CommandGroupPlacement` you pass). Pair with `GitTicketsMyIssuesCommands { showingMyIssues = true }` for the Phase 2 list. Both items carry default SF Symbol icons (`exclamationmark.bubble` + `tray`).
- AppKit: `GitTicketsMenuItemFactory.makeReportIssueItem()` returns an `NSMenuItem` (with the matching SF Symbol set on `item.image`) wired to `ReportWindowController.shared` by default.
- UIKit: `present(UINavigationController(rootViewController: GitTicketsViewController()), animated: true)`. The view controller subclasses `UIHostingController<GitTicketsView>` and ships with `title = "Report an Issue"`.

## Module layout

See [Build Sequence](Build-Sequence) for the PR ordering. The file tree under `Sources/GitTickets/`:

- `PublicAPI/` — `GitTickets.swift`, `Configuration.swift`, `AuthMode.swift`, `Models.swift` (incl. `IssueComment` + `CachedReport`), errors, theme.
- `Auth/` — `IssueSubmitter` protocol; `Relay/` (HMAC, payload, client, submitter); `DeviceFlow/` (coordinator, token store, submitter).
- `Networking/` — `HTTPClient`, `RateLimitBackoff`, `UserAgent`. The two submitters each own their GitHub-side API calls (relay path → `RelayClient`; device-flow path → inline `GET /repos/.../issues/N` + `/comments` helpers on `DeviceFlowSubmitter`).
- `Storage/` — `SubmissionCache` (SQLite), `DeviceIdentity`, `TokenStore`, `Keychain` wrapper.
- `Diagnostics/` — collector, blob, redaction pipeline, `OSLogTailer`, `DeviceInfo`.
- `Screenshot/` — platform impls (macOS uses `ScreenCaptureKit` on macOS 14+ with a 13 fallback; iOS uses `UIGraphicsImageRenderer`).
- `UI/SwiftUI/`, `UI/AppKit/`, `UI/UIKit/` — the three integration paths plus the redesigned form / detail / My Reports views.
- `Bodybuilder/` — assembles the markdown body, embeds the correlation marker; ships an `extractUserBody(from:)` helper that the detail view's "Your report" card uses to strip the diagnostics block + marker.

## Phase 2 — My Issues

Submission IDs are UUIDs embedded as `<!-- gittickets-id: UUID -->` HTML comments in the issue body. The SDK caches every submitted ID + the assembled body + the kind locally (SQLite). `GitTicketsMyIssuesView` reads `GitTickets.cachedSubmissions()` for instant first paint and `GitTickets.refreshMyIssues()` to ask the active submitter for fresh state.

- **Relay path**: `POST {relayURL}/my-issues` with the local ID list. Relay does `GET /repos/.../issues?labels=gittickets&state=all`, matches embedded UUIDs server-side, returns metadata + comment counts. Comments load via `POST {relayURL}/comments` per opened issue.
- **Device Flow path**: SDK walks the cache's known issue numbers and `GET /repos/.../issues/N` per record (cheaper than walking GitHub Search). Comments load via `GET /repos/.../issues/N/comments` directly with the user's token. A 401 from either endpoint wipes the dead token and throws `.deviceFlowNotAuthorized` so the form re-prompts.

Tapping a row opens `IssueDetailView` which surfaces three sections: the cached issue body (via `GitTickets.cachedReport(for:)`), an "Open on GitHub" link, and the comment thread rendered through `AttributedString(markdown:)` with `interpretedSyntax: .inlineOnlyPreservingWhitespace`. Mark-as-read state lives in SQLite via `GitTickets.markRepliesRead(submissionID:count:)`.

## Theming

`GitTicketsTheme` (accent override, three fonts, corner radius, header image source enum, submit button style enum) reaches the views via two paths, in precedence order:

1. `Configuration.theme` — set at app launch via `GitTickets.configure(_:)`. The top-level views (`GitTicketsView`, `GitTicketsMyIssuesView`, `IssueDetailView`) all resolve `configuration?.theme ?? envTheme`, so this wins for most adopters.
2. `\.gitTicketsTheme` SwiftUI environment value — useful when you want a per-presentation override without rewiring `Configuration`.

Defaults inherit the host app's `Color.accentColor` and use system semantic surface colors (`.windowBackgroundColor` / `.systemGroupedBackground` etc.), so the package adapts to light/dark and any host accent automatically. The visual look + tokens for the v1.0 design come from `design/design_handoff_gittickets_views_generic/` — see [the design folder's README](../design/design_handoff_gittickets_views_generic/README.md) for the full equivalences table.

## What we deliberately don't do

- Don't ship a PAT-in-binary mode. Documented in [Threat Model](Threat-Model).
- Don't auto-capture screenshots. User must tap "Add Screenshot."
- Don't bundle fonts or color assets. Borrowed appearance beats imposed appearance.
- Don't depend on any production Swift package. System frameworks only.
- Don't try to render `.github/ISSUE_TEMPLATE/*.yml` Issue Forms in v1 — see [Footgun — Issue Forms Are Web-UI-Only](../.memory/footguns/) (web-UI-only field semantics; the GitHub API exposes raw markdown). v1.1 candidate.

---
_Last updated: 2026-06-06 — refreshed for v1.0 shipped (UI inits + Phase 2 paths + theming precedence)_
