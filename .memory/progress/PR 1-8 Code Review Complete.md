---
title: PR 1-8 Code Review Complete
type: note
permalink: gittickets/progress/pr-1-8-code-review-complete
tags:
- progress
- code-review
- security
- footguns
---

Multi-angle code review of PRs 1–8 (bootstrap → relay submitter) ran on 2026-06-04. 24 findings across crypto, networking, redaction, multipart, Keychain, concurrency, markdown, storage, tests, and API surface — all fixed in the same session. Build clean on macOS + iOS; 129 tests pass including 14 new regression tests.

## Observations

- [count] 24 findings: 15 in the ranked output + 9 cut-for-cap that were still real and got fixed. #review
- [coverage] 9 finder angles (line-by-line diff, contract/invariant, cross-file tracer, Swift/Apple pitfalls, wrapper correctness, reuse, simplification, efficiency, altitude) ran in parallel via subagents. 1-vote verifier per candidate; sweep agent surfaced 8 more. See the review skill output. #review
- [biggest-bugs] OneShotStream double-resume crash on macOS 13; HMAC timestamp stale across retries; HTTPClient retries POST on transport error (duplicate issues); IPv4 redactor matches version strings; IPv6 redactor matches HH:MM:SS; multipart filename injection; SQLite cache 0644; Keychain global service identifier. #review
- [lessons-captured] Seven new footguns in `.memory/footguns/` and one consolidated wiki page at `wiki/Patterns-and-Gotchas.md` index the durable rules. Threat Model now links them all. #docs
- [test-pattern] 14 regression tests added — each names the finding it covers in a comment so future churn can't quietly drop the regression. #testing
- [public-api-changes] `SubmittedIssue.missingLabels` added; `Report.init(diagnostics: DiagnosticsBlob?)` overload added; `GitTicketsImageSource.named` changed from `(String, bundle: Bundle)` to `(String, bundleIdentifier: String?)`. Pre-1.0, no migration concern. #api
- [wire-format-changes] `RelayReportRequest` dropped `kind` and `userAgent` body fields; `RelayReportResponse` added `appliedLabels`; `RelayErrorEnvelope` added `byteLimit`; `MyIssuesRequest` has its own `currentSchemaVersion`. Document loudly in PR 9 (relay templates). #wire-format
- [docs-drift-fixed] `wiki/Relay-Deployment.md` curl recipe now uses `printf '%s.%s' "$TIMESTAMP" "$BODY"` to match `RelaySignature.swift`. Was `%s%s` (no separator) — would have made every integrator's relay reject every real client. #docs

## Relations

- closes [[Footgun — HMAC Signature Stale on Retry]] in production code
- closes [[Footgun — Retry Non-Idempotent POST Without Idempotency Key]] in production code
- closes [[Footgun — Redactor Regexes Over-Match]] in production code
- closes [[Footgun — Multipart Header Injection via Filename and MIME]] in production code
- closes [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]] in production code
- closes [[Footgun — Sendable Lies in Public Types]] in production code
- closes [[Footgun — Markdown Injection in GitHub Issue Body]] in production code
- closes [[Footgun — SQLite Cache File Default Permissions]] in production code
- updates [[Footgun — Labels and Assignees Silently Dropped]] with the SubmittedIssue.missingLabels surface
- adds [[Patterns and Gotchas]]
- gates [[PR 9 Complete — Vercel Relay]] (must match new wire format)
