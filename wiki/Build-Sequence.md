---
title: Build-Sequence
type: note
permalink: gittickets-wiki/build-sequence
---

# Build Sequence

The 20 ordered PRs that ship v1.0. Each PR is one merge; later PRs depend on earlier ones. Source of truth for what lands and in what order.

| # | PR | Summary | Verifies |
| --- | --- | --- | --- |
| 1 | Bootstrap | `Package.swift`, `LICENSE`, CI, repo skeleton, stub `GitTickets.configure` | Build system itself |
| 2 | Public API skeleton | All `public` types with stub bodies, doc comments | Public surface compiles |
| 3 | Models + body builder | `Report`, `SubmittedIssue`, `IssueBodyBuilder`, `CorrelationMarker` | Markdown body shape |
| 4 | Storage | `SubmissionCache` (SQLite), `DeviceIdentity`, `Keychain` | Local persistence |
| 5 | Diagnostics | Collector, blob, redaction pipeline, `OSLogTailer`, `DeviceInfo` | Diagnostic correctness + redaction |
| 6 | Screenshot | Platform impls | Capture works on both platforms |
| 7 | Networking core | `HTTPClient`, `RateLimitBackoff`, `UserAgent` | Mocked HTTP behavior |
| 8 | Relay submitter | `RelaySubmitter`, HMAC signing | Wire format against vector |
| 9 | Vercel relay | Full impl + deploy verification | Real round-trip to GitHub |
| 10 | Cloudflare Worker | Parity with Vercel | Worker round-trip |
| 11 | Device Flow submitter | Full state machine + Keychain | All state transitions |
| 12 | SwiftUI form | `GitTicketsView`, fields, banner, screenshot thumb, device flow sheet | Snapshot tests, manual end-to-end |
| 13 | SwiftUI Commands + AppKit factory | `GitTicketsCommands`, `GitTicketsMenuItemFactory` | MacSampleApp menu integration |
| 14 | UIKit container | `GitTicketsViewController` | iOSSampleApp UIKit variant |
| 15 | My Issues | List, detail, markdown comments, polling | Reply round-trip |
| 16 | Theming polish | Environment plumbing, defaults audit, snapshot tests | Light/dark / accent inheritance |
| 17 | Documentation pass | All `docs/*`, `relay/README.md`, getting-started | Full adopter walkthrough |
| 18 | Privacy manifest | `PrivacyInfo.xcprivacy` | Apple's manifest validator |
| 19 | Examples polish | Three sample apps end-to-end against a real relay | Adopter onboarding flow |
| 20 | Release | Tag `v1.0.0` SDK + relay templates independently | Public availability |

Each PR ends with the manual verification step from its row, plus passing CI.

The current open kanban tracking these PRs lives in `TASKS.md` at the repo root.

---
_Last updated: 2026-06-04 — initial build plan_
