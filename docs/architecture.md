# Architecture

GitTickets is a client SDK + an optional relay. The SDK is everything the
adopter's app links against; the relay is ~10 files of TypeScript the
adopter deploys once.

## Component map

```
┌────────────────────────────────────────────────────────────────┐
│                      Adopter's app (host)                       │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                   GitTickets SDK (this)                    │  │
│  │                                                            │  │
│  │  Public surface:                                           │  │
│  │   • GitTickets.configure(_:) / .submit(_:)                 │  │
│  │   • GitTicketsView (SwiftUI form)                          │  │
│  │   • GitTicketsViewController (UIKit container)             │  │
│  │   • GitTicketsCommands (SwiftUI commands)                  │  │
│  │   • GitTicketsMenuItemFactory + ReportWindowController (AppKit) │
│  │                                                            │  │
│  │  Internal:                                                 │  │
│  │   • RelaySubmitter ────┐                                   │  │
│  │   • DeviceFlowSubmitter ─┐                                 │  │
│  │   • SubmissionCache (SQLite)                               │  │
│  │   • DiagnosticsCollector + Redactors                       │  │
│  │   • ScreenshotCapture                                      │  │
│  │   • TokenStore (Keychain)                                  │  │
│  │   • DeviceIdentity (Keychain)                              │  │
│  └────────────────────────┬──────────────────────────────┬────┘  │
└───────────────────────────┼──────────────────────────────┼───────┘
                            │                              │
                            │ HMAC-signed POST              │ OAuth-bearer POST
                            │                              │
                            ▼                              ▼
   ┌──────────────────────────────────┐    ┌─────────────────────────────┐
   │  Adopter-hosted relay             │    │      api.github.com         │
   │  (Vercel Function / CF Worker)    │    │   /repos/:owner/:name/issues │
   │                                   │    │                             │
   │  Verifies HMAC + rate-limit +     │    │  (Device Flow path posts    │
   │  idempotency, then forwards to    │    │   directly here with the    │
   │  GitHub as a GitHub App.          │    │   user's OAuth token)       │
   └──────────────┬───────────────────┘    └─────────────────────────────┘
                  │
                  │ GitHub App installation token
                  │
                  ▼
   ┌──────────────────────────────────┐
   │            api.github.com         │
   │   /repos/:owner/:name/issues      │
   └──────────────────────────────────┘
```

## Two auth modes

The SDK dispatches based on `Configuration.auth`. Both modes converge on
the same `IssueSubmitter` protocol so the UI layer never branches.

### `.relay` (most apps)

- SDK signs each request with HMAC-SHA256 over `"<timestamp>.<body>"`.
- Relay verifies, rate-limits, deduplicates by `submissionID`, and POSTs
  to GitHub using a GitHub App installation token scoped to **Issues:
  Write** on a single repo.
- Attachments upload to the relay's blob store first (Vercel Blob or R2);
  the returned URL gets inlined into the issue body markdown.

### `.deviceFlow` (developer-tool apps)

- SDK runs the OAuth Device Flow against `github.com/login/device/code`
  and `/login/oauth/access_token`.
- On success, the user-scoped token persists in the Keychain via
  `TokenStore`.
- Subsequent submissions POST directly to GitHub Issues API with `Bearer
  <token>`.
- No image attachments — GitHub has no public attachment upload API and
  Device Flow has no relay-side storage.

## Submission pipeline

```
 user fills form  →  ScreenshotCapture (optional, user-initiated)
                  →  DiagnosticsCollector.collect(policy:)
                  →  Redactor pipeline (single pass, before display)
                  →  Form renders preview — user reviews exact blob
                  →  user taps Submit
                  →  Report built (title, body, attachments, blob)
                  →  IssueSubmitter.submit(report)
                       • SubmissionCache.record(id:)? → return cached (dedupe)
                       • Upload attachments (relay only)
                       • IssueBodyBuilder.build(...)  (assembles markdown + correlation marker)
                       • POST /report (or /repos/:owner/:name/issues)
                       • Map status code → GitTicketsError if non-2xx
                       • SubmissionCache.upsert(record)
                       • Return SubmittedIssue
                  →  Form shows success state with issue # + "Open on GitHub"
```

## Data stored locally

- **`SubmissionCache`** (SQLite at `~/Library/Application Support/GitTickets/submissions.sqlite`):
  past submissions for the "My Issues" view, including reply counts and
  read state.
- **`DeviceIdentity`** (Keychain, namespaced by host bundle identifier):
  the per-install UUID.
- **`TokenStore`** (Keychain, namespaced by host bundle identifier):
  the OAuth access token, when using `.deviceFlow`.

All three respect the Keychain-namespacing and SQLite-file-permissions
defenses documented under `.memory/footguns/` — service identifiers are
namespaced by host bundle id so two same-team apps don't collide, items
opt out of iCloud Keychain sync, and the SQLite file is mode 0o600.

## Cross-cutting concerns

- **Diagnostics-vs-display invariant**: the redacted blob the user sees is
  byte-identical to what's posted. The submitter never re-collects. See
  [`diagnostics.md`](diagnostics.md).
- **Theme propagation**: `\.gitTicketsTheme` environment value reaches
  every subview. Defaults inherit the host's `Color.accentColor` and
  system fonts. See [`theming.md`](theming.md).
- **Sendable**: every public type is `Sendable`. The submitters are
  stateless beyond their injected dependencies; the form's state is
  SwiftUI-owned and lives in `@State` props.
