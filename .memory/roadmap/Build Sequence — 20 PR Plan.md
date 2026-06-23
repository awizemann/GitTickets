---
title: Build Sequence — 20 PR Plan
type: note
permalink: gittickets/roadmap/build-sequence-20-pr-plan
tags:
- roadmap
- build-plan
status: resolved
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

The v1 build is decomposed into 20 ordered PRs. Each is one merge; later PRs depend on earlier ones. Source of truth for what ships in v1.

## Observations

- [step] PR 1: Bootstrap — Package.swift, LICENSE, CI, repo skeleton. Stub `GitTickets.configure` throws `.notConfigured`. #pr
- [step] PR 2: Public API skeleton — all `public` types with stub bodies. Compiles, doc comments present. #pr
- [step] PR 3: Models + body builder — `Report`, `SubmittedIssue`, `IssueBodyBuilder`, `CorrelationMarker`, templates per kind. #pr
- [step] PR 4: Storage — `SubmissionCache` (SQLite), `DeviceIdentity`, `Keychain` wrapper. #pr
- [step] PR 5: Diagnostics — collector, blob, redaction pipeline, OSLog tailer, device info. #pr
- [step] PR 6: Screenshot — platform impls. #pr
- [step] PR 7: Networking core — HTTPClient, RateLimitBackoff, UserAgent. #pr
- [step] PR 8: Relay submitter — RelaySubmitter, HMAC signing, RelayClient. #pr
- [step] PR 9: Vercel relay — full impl + tests + deploy verification. #pr
- [step] PR 10: Cloudflare Worker — parity with Vercel. #pr
- [step] PR 11: Device Flow submitter — full state machine + Keychain token store. #pr
- [step] PR 12: SwiftUI form — GitTicketsView, fields, banner, screenshot thumb, device flow sheet. #pr
- [step] PR 13: SwiftUI Commands + AppKit factory — GitTicketsCommands, GitTicketsMenuItemFactory. #pr
- [step] PR 14: UIKit container — GitTicketsViewController. #pr
- [step] PR 15: My Issues — list, detail, markdown comments, cache integration, polling. #pr
- [step] PR 16: Theming polish — environment plumbing, defaults audit, snapshot tests. #pr
- [step] PR 17: Documentation pass — docs/* + relay README + getting-started. #pr
- [step] PR 18: Privacy manifest — `PrivacyInfo.xcprivacy` validated. #pr
- [step] PR 19: Examples polish — three sample apps end-to-end. #pr
- [step] PR 20: Release — tag v1.0.0 SDK + relay templates independently. #pr

## Relations

- realizes [[Architecture — Client SDK + Optional Relay]]
- tracked_in TASKS.md
