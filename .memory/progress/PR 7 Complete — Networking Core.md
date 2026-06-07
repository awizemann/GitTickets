---
title: PR 7 Complete — Networking Core
type: note
permalink: gittickets/progress/pr-7-complete-networking-core
tags:
- progress
- pr-7
- networking
---

PR 7 (Networking core) shipped 2026-06-04. HTTPClient is the transport substrate PR 8 (relay submitter) and PR 11 (Device Flow) build on.

## Observations

- [verified] 93/93 tests green on macOS. iOS Sim build clean. #verification
- [files-shipped] `Sources/GitTickets/Networking/` — `UserAgent.swift`, `RateLimitBackoff.swift`, `HTTPClient.swift`. Plus `MockURLProtocol` in tests. #files
- [decision] HTTPClient explicitly does NOT retry 4xx, including 429. The relay submitter inspects `Retry-After` and surfaces `GitTicketsError.rateLimited`. Auto-retrying 429 from inside the transport would race with the user-visible "rate limited" state. #pattern
- [decision] HTTPClient DOES retry transport errors and 5xx, up to `maxAttempts` (default 3), with exponential backoff via `RateLimitBackoff`. Caps at 30s. #pattern
- [decision] User-Agent format: `GitTickets/<sdkVersion> (<platform>; <DeviceInfo>; <osVersion>) <appName>/<appVersion>`. Surfaces enough context that GitHub abuse heuristics see a real app, not just "GitHub-CLI/2.0" or empty UA. #wire-format
- [decision] If the caller has already set User-Agent on the request, HTTPClient does NOT override. Lets Device Flow set its own UA for github.com requests when needed. #pattern
- [decision] `HTTPResponse.header(_:)` is case-insensitive (per RFC 7230 §3.2 — header names are case-insensitive). #pattern
- [decision] `RateLimitBackoff.parseRetryAfter` supports both delta-seconds and HTTP-date forms. Returns `nil` for nonsense rather than throwing — the caller surfaces "unknown retry-after" gracefully. #pattern
- [decision] `MockURLProtocol` in tests uses a class-level dictionary mapping URL → closure. Cleared in setUp/tearDown. `@unchecked Sendable` since the test serializes access. Simpler than URLSessionMock libraries. #testing
- [tech-debt] `Date()` use in `RateLimitBackoff.parseRetryAfter` for "now" — tests pass `now:` explicitly to keep deterministic. Production callers can rely on the default. #pattern
- [decision] `sdkVersion = "1.0.0-dev"` constant in `UserAgent.swift`. PR 20 (release) bumps this to `"1.0.0"`. #release

## Relations

- precedes PR-8-Relay-Submitter
- realizes [[Architecture — Client SDK + Optional Relay]]
- follows [[PR 6 Complete — Screenshot Capture]]
