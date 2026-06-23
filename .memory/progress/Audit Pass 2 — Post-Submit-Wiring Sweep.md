---
title: Audit Pass 2 — Post-Submit-Wiring Sweep
type: note
permalink: gittickets/progress/audit-pass-2-post-submit-wiring-sweep
tags:
- progress
- code-review
- audit
- phase-2
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

Multi-angle audit triggered by the discovery that `GitTickets.submit(_:)` had been a PR-2 stub the whole time. Three parallel Explore agents (stub/TODO hunter, public-API reachability, Vercel/Cloudflare parity). Total findings: 27; actionable now: 5; deferred: rest.

## Observations

- [verified] 134/134 Swift tests green (was 130 — added 4 new tests for the fetch path). 32/32 Cloudflare tests green after byteLimit fix. iOS Sim build clean. #verification
- [fix-shipped] `RelaySubmitter.fetchMyIssues` + `fetchReplies` implemented. Previously the protocol's throws-not-supported default was inherited silently — same shape as the just-fixed submit() stub. Both now hit the relay's `/my-issues` endpoint via `RelayClient.fetchMyIssues`, merge with cache (cache holds the canonical "read" state so unreadReplyCount stays correct across launches), and update the cache best-effort. #fix
- [fix-shipped] Cloudflare attachment.ts envelope-too-large path: was returning 413 with `byteLimit: MAX_BODY_BYTES` (10 MB envelope ceiling) which would mislead clients into reporting a 10 MB per-file cap when the configured limit is 5 MB. Now returns `body_too_large` matching Vercel, no `byteLimit` field. The `byteLimit` field is reserved for the configured per-attachment cap. #fix
- [fix-shipped] Stale doc strings scrubbed: removed "lands in PR 11" / "ships in PR 12+" / "in this skeleton" / "currently throws" language from `GitTickets.swift`, `IssueSubmitter.swift`, `AuthMode.swift`, `DiagnosticsCollector.swift`, `ScreenshotCapture.swift`. Replaced with "not yet implemented" / functional descriptions of current state. Internal PR numbers should never leak into adopter-facing API docs. #fix
- [fix-shipped] `AuthMode.deviceFlow` + `.mock` cases now carry "Not yet implemented" / "Not dispatched in production" notes in their docstrings, plus the resolver error messages point to `.relay` as the working alternative. #fix
- [new-tests] 4 regression tests in `RelaySubmitterTests`: `fetchMyIssues` cache-merge happy path; empty input short-circuits; `fetchReplies` delegates and surfaces; unknown submission returns (0, nil). The new tests will catch any future regression where the protocol method falls back to the throwing default. #testing
- [done] Phase 2 UI surface (GitTicketsView, GitTicketsCommands, GitTicketsMenuItemFactory, GitTicketsMyIssuesView, GitTicketsViewController) — all shipped: PR 12 (GitTicketsView + DeviceFlowSheet), PR 13 (GitTicketsCommands + GitTicketsMenuItemFactory + ReportWindowController), PR 14 (GitTicketsViewController), PR 15 (GitTicketsMyIssuesView + IssueDetailView + MarkdownCommentView). #scope
- [done] `GitTicketsTheme.*` fields (accentColor, titleFont, bodyFont, monospacedFont, cornerRadius, headerImage, submitButtonStyle) — all consumed in PR 12 (the first five) and PR 16 (HeaderImage + submitButton @ViewBuilder closed headerImage + submitButtonStyle). Audit-loop closed. #scope
- [done] `SubmissionCache.markRepliesRead` — wired in PR 15 via `IssueDetailView.task` + the public static `GitTickets.markRepliesRead(submissionID:count:)` so adopters with custom UIs can call it too. #scope
- [done] `UserAgent.sdkVersion` — bumped from `1.0.0-dev` to `1.0.0` for the v1.0.0 release (commit 014b8d4, tag v1.0.0) and then to `1.1.0` for the v1.1.0 Swift 6 release-prep (commit a52e505, push pending Memophant validation). #release
- [pattern] Audit method that paid off: three parallel agents covering different angles (stub/TODO, reachability, cross-relay parity). Each found genuinely different findings. Parallelism > one-deep-pass for this kind of "sweep before shipping" check. #review-pattern
- [shape-match] All three actionable bugs share a shape: "infrastructure exists but the public-API dispatch never reached it." submit() (fixed earlier), fetchMyIssues/fetchReplies (this pass), Cloudflare envelope byteLimit (silent contract drift). Look for this shape in every future review. #pattern

## Relations

- follows [[Memophant Integration Complete — Help → Report an Issue]]
- closes [[PR 1-8 Code Review Complete]] residual items
- precedes PR-11-Device-Flow-Submitter
