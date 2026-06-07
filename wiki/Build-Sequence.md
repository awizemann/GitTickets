---
title: Build-Sequence
type: note
permalink: gittickets-wiki/build-sequence
---

# Build Sequence

The 20 ordered PRs that shipped v1.0. Each PR was one merge; later PRs depended on earlier ones. This page is now a **historical record** — see [`CHANGELOG.md`](../CHANGELOG.md) for the formal release notes.

## Status: ✅ all 20 PRs landed (2026-06-04 → 2026-06-06)

| # | PR | Summary | Status |
| --- | --- | --- | --- |
| 1 | Bootstrap | `Package.swift`, `LICENSE`, CI, repo skeleton, stub `GitTickets.configure` | ✅ |
| 2 | Public API skeleton | All `public` types with stub bodies, doc comments | ✅ |
| 3 | Models + body builder | `Report`, `SubmittedIssue`, `IssueBodyBuilder`, `CorrelationMarker` | ✅ |
| 4 | Storage | `SubmissionCache` (SQLite), `DeviceIdentity`, `Keychain` | ✅ |
| 5 | Diagnostics | Collector, blob, redaction pipeline, `OSLogTailer`, `DeviceInfo` | ✅ |
| 6 | Screenshot | ScreenCaptureKit on macOS, `UIWindow.drawHierarchy` on iOS | ✅ |
| 7 | Networking core | `HTTPClient`, `RateLimitBackoff`, `UserAgent` | ✅ |
| 8 | Relay submitter | `RelaySubmitter`, HMAC signing | ✅ |
| 9 | Vercel relay | Full impl, GitHub round-trip verified | ✅ |
| 10 | Cloudflare Worker | Parity with Vercel; R2 + KV | ✅ |
| 11 | Device Flow submitter | Full state machine + Keychain `TokenStore` | ✅ |
| 12 | SwiftUI form | `GitTicketsView`, fields, banner, screenshot thumb, `DeviceFlowSheet` | ✅ |
| 13 | SwiftUI Commands + AppKit factory | `GitTicketsCommands`, `GitTicketsMenuItemFactory`, `ReportWindowController` | ✅ |
| 14 | UIKit container | `GitTicketsViewController` (UIHostingController subclass) | ✅ |
| 15 | My Issues | `GitTicketsMyIssuesView`, `IssueDetailView`, `MarkdownCommentView`, `/comments` relay endpoint | ✅ |
| 16 | Theming polish | Environment plumbing, `headerImage` + `submitButtonStyle` wiring, snapshot tests | ✅ |
| 17 | Documentation pass | All `docs/*` + relay READMEs | ✅ |
| 18 | Privacy manifest | `PrivacyInfo.xcprivacy` declared as target resource | ✅ |
| 19 | Examples polish | `Examples/MacSampleApp`, `iOSSampleApp`, `AppKitSampleApp` reference code | ✅ |
| 20 | Release | Version bump + CHANGELOG; tag-and-push held for user-controlled sequencing | ☑️ source-prep done |

## Post-build additions

After the 20-PR plan completed, two design handoffs from Claude Design landed:

- Visual redesign of `GitTicketsView` and `IssueDetailView` — integrated into the package alongside `GTSurface`, `GTSemantic`, `KindBadge`, `StatusBadge`, `TrustBanner`, `DiagnosticsCard`, and friends. See [`design/design_handoff_gittickets_views_generic/`](../design/design_handoff_gittickets_views_generic/).
- Visual redesign of `GitTicketsMyIssuesView` — `MyReportRow` with kind icon tile, status dot, "N NEW" capsule.
- `GitTicketsCommands` + `GitTicketsMyIssuesCommands` + `GitTicketsMenuItemFactory` gained leading SF Symbol icons in their menu items.

Each design pass was integrated as a fresh layer on top of the v1.0 baseline rather than amending the PR-history. The current `TASKS.md` board tracks anything still open.

---
_Last updated: 2026-06-06 — converted from forward-plan to shipped-record_
