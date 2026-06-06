---
title: Patterns-and-Gotchas
type: note
permalink: gittickets-wiki/patterns-and-gotchas
---

# Patterns and Gotchas

Durable lessons surfaced by the PR 1–8 code review. Each pattern below pairs a concrete trap we hit with the convention that prevents it. Use this as the "things to check on every PR touching X" reference.

Detailed per-issue write-ups live in `.memory/footguns/` — this page is the index + cheat sheet.

## HMAC and request signing

**Trap:** Compute timestamp + signature once, then hand the signed request to a retry loop. Retries replay the stale timestamp; the relay's 5-minute window elapses; transient 5xx surfaces as `signatureMismatch`.

**Rule:** Re-sign on every retry attempt. `HTTPClient.sendRetrying(buildRequest:)` takes a closure that runs before each attempt; the relay client computes timestamp + signature inside that closure.

**Trap:** Wiki documents the HMAC canonical string one way; Swift code computes it another. Integrators following the docs build a relay that rejects every real client.

**Rule:** The canonical string is `"<timestamp>.<body>"` — literal `.` separator. Pinned in `RelaySignature.swift`, `wiki/Relay-Deployment.md`, and `Tests/.../RelaySignatureTests.test_signMatchesIndependentHmacComputation`. Changing any of those three changes the wire format; bump SDK + relay templates major version together.

**Trap:** `if expected.count != signature.count { return false }` defeats constant-time comparison.

**Rule:** XOR over a fixed window (length of expected), fold the length check into the diff. `RelaySignature.verify` is the reference. CryptoKit ships `HMAC.isValidAuthenticationCode(_:authenticating:using:)` for the raw-MAC path.

**Trap:** JSON encoder without `.sortedKeys` produces non-deterministic byte ordering — the signature doesn't validate on the receiving side.

**Rule:** `RelayJSON.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]`. Any new endpoint that signs JSON inherits this.

Detail: [[Footgun — HMAC Signature Stale on Retry]]

## Networking retry and idempotency

**Trap:** Retry-on-error loop replays POST `/report` after a transport drop. The relay had already created the GitHub issue but the response was lost — second submit creates a duplicate.

**Rule:** Retry 5xx for ALL methods; retry transport errors ONLY for idempotent methods (GET/HEAD/OPTIONS). HTTPClient.sendRetrying enforces this structurally via `isIdempotent(request)`. POSTs throw on transport error.

**Rule:** Every POST through `RelayClient` carries `X-GitTickets-Idempotency-Key` derived from `submissionID`. Relay versions that record the key can short-circuit retries.

**Rule:** `RelaySubmitter.submit` checks `SubmissionCache.record(submissionID:)` BEFORE submitting and returns the cached result if present. Closes the UI double-tap and the SDK-level retry windows.

**Trap:** `maxAttempts == 0` skips the request loop entirely and throws `URLError(.unknown)` with no transport ever firing.

**Rule:** Clamp at config init: `self.maxAttempts = max(1, maxAttempts)`.

**Trap:** Exponential backoff with no jitter — N clients failing simultaneously retry in lockstep against a recovering relay.

**Rule:** `RateLimitBackoff.exponentialDelay(..., jitter: true)` (the default) scales by `[0.5, 1.5)`. Pass `jitter: false` in tests that assert exact growth shape.

**Trap:** 5xx retries ignore `Retry-After` headers. Servers asking for a longer cool-off get hammered anyway.

**Rule:** `HTTPClient.retryDelay(for:attempt:)` parses `Retry-After` on both 5xx and 429. `RateLimitBackoff.parseRetryAfter` handles all three HTTP-date forms (IMF-fixdate, RFC 850, asctime) plus delta-seconds.

Detail: [[Footgun — Retry Non-Idempotent POST Without Idempotency Key]]

## Redaction regex pitfalls

**Trap:** IPv4 regex matches version strings (`App: MyApp 1.0.0 (1.0.0.123)` → `App: MyApp 1.0.0 ([ip redacted])`).

**Rule:** Use strict octet validation (0–255 each) AND exclude paren/dot/digit context on both sides: `(?<![0-9.(])...(?![0-9.)])`. Cannot perfectly disambiguate, but covers the common in-parens case.

**Trap:** IPv6 regex with case-insensitive `[A-F0-9]` matches `HH:MM:SS` clock timestamps. Also fails `::1` because `\b` requires a word-char on at least one side of the leading `:`.

**Rule:** Require lookahead that the match contains at least one hex letter OR a `::` zero-compression marker. Replace `\b` with `(?<![A-F0-9:])` / `(?![A-F0-9:])`.

**Trap:** Default redactor order is `[email, ipv4, ipv6, bearer]`. An IPv4-shaped substring inside a Bearer token gets rewritten to `[ip redacted]`, corrupting the bearer charset so the bearer regex no longer matches; the leftover JWT halves leak.

**Rule:** Default order is `[bearer, email, ipv4, ipv6]`. Bearer runs first so embedded IPs in tokens don't break the token-charset match.

**Rule:** When adding any redactor, test against the REAL diagnostics blob shape — timestamps, version strings, file paths, log lines. Abstract regex tests miss the over-match cases. See `RedactionPipelineTests.test_realisticBlobWithEverything` for the fixture pattern.

Detail: [[Footgun — Redactor Regexes Over-Match]]

## Markdown injection in issue body

**Trap:** Wrap diagnostics in static ` ```text ` fence. Inner ``` from a log line closes the fence early; the rest of the body — including the correlation marker — renders as prose.

**Rule:** `IssueBodyBuilder.fenceFor(_:)` scans inner content for the longest backtick run and picks a fence one longer. GFM closes on equal-or-longer; the outer must always be strictly longer.

**Trap:** `![screenshot](\(url.absoluteString))` interpolates URLs into markdown link parentheticals. URLs with `)` (R2 / Vercel Blob presigned URLs can have one) terminate the link target early.

**Rule:** Percent-encode `(` and `)` in markdown URL targets via `IssueBodyBuilder.escapeURLForMarkdown(_:)`.

**Trap:** `[\(filename)](url)` with `[` or `]` in the filename breaks the markdown link grammar.

**Rule:** Escape `\`, `[`, `]` in display text via `IssueBodyBuilder.escapeMarkdownLinkText(_:)`.

**Rule:** When the body contains a parser anchor (the correlation marker), test that adversarial inputs upstream can't move or hide it. See `IssueBodyBuilderTests.test_diagnosticsContainingBackticksKeepsFenceClosed`.

Detail: [[Footgun — Markdown Injection in GitHub Issue Body]]

## Multipart header injection

**Trap:** Interpolate caller-supplied filename / MIME directly into `Content-Disposition` / `Content-Type` headers. CRLF in filename injects extra headers; `"` closes the quoted-string; boundary token in filename terminates the body.

**Rule:** `RelayClient.sanitizeFilename` strips control chars, quotes, backslashes; replaces `/` and `:` with `_`; caps length; falls back to `"attachment"` if empty.

**Rule:** `RelayClient.validateMimeType` enforces a small allowlist (`image/{png,jpeg,gif,webp,heic}`, `application/octet-stream`, `text/plain`) AND explicitly rejects CR/LF as defense-in-depth.

**Rule:** Multipart boundary stays a UUID — unpredictable. If the boundary is ever made guessable (sequential, derived from request id), filename injection becomes exploitable even after sanitization.

**Rule:** The relay should ALSO validate filename/MIME server-side. Don't trust client sanitization alone; the relay is the trust boundary.

Detail: [[Footgun — Multipart Header Injection via Filename and MIME]]

## Keychain conventions

**Trap:** `SecItemCopyMatching` defaults `kSecAttrSynchronizable` to `Any`. A read can match iCloud-synced items written by a sibling install on another device.

**Rule:** Every Keychain query (read, write, delete) sets `kSecAttrSynchronizable: kCFBooleanFalse` explicitly. The wrapper handles this; don't bypass.

**Trap:** Global service identifier shared across all GitTickets-using apps on a device. Same-team apps on macOS share Keychain → they read the same UUID.

**Rule:** Service identifier is namespaced by host bundle ID: `DeviceIdentity.defaultServicePrefix + "." + Bundle.main.bundleIdentifier`. Per-app isolation by default.

**Rule:** Expose access group + service overrides on `DeviceIdentity.init` so hosts that DO want cross-app identity (shared App Group) can opt in. Default is isolation; sharing is explicit.

**Trap:** Docstring promises "survives reinstall" but the access group is never wired. Since iOS 10.3, Keychain items for uninstalled apps are purged unless declared in an explicit access group + entitlement.

**Rule:** Don't promise survive-reinstall unless the API surface lets the caller pass the access group. Document "per-install" as the default, "survives reinstall" as opt-in.

Detail: [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]]

## SQLite cache and on-disk files

**Trap:** `sqlite3_open_v2` creates the file with the process umask (0644). On non-sandboxed macOS, any local user can read the cache.

**Rule:** Immediately `FileManager.setAttributes([.posixPermissions: 0o600])` after open. Also chmod the `-wal` and `-shm` siblings. See `SubmissionCache.restrictPermissions(at:)`.

**Rule:** Default to 0600 for ANY file the SDK creates (cache, screenshot temp, export bundles). Widen only with a stated reason.

**Trap:** Best-effort writes silently swallowed (e.g., `try? cache.upsert(record)`). Host has no signal when the cache stopped working.

**Rule:** Pair `try?` with a `GitTicketsLogger?.log(.warning, ...)` so hosts that wired up a logger see the failure even when the call site doesn't throw.

Detail: [[Footgun — SQLite Cache File Default Permissions]]

## Swift concurrency and Sendable

**Trap:** `private nonisolated(unsafe) static var _configuration: Configuration?` for a struct containing URL + Data + nested structs. `nonisolated(unsafe)` suppresses the Sendable check but does NOT make multi-word value assignment atomic. Concurrent configure+read returns a torn struct → crash in release.

**Rule:** Use an `NSLock`-guarded box (or `OSAllocatedUnfairLock`, or an `actor`) for ANY static mutable state holding a non-trivial value type. `GitTickets.configurationStorage` is the reference.

**Trap:** `enum GitTicketsImageSource: Sendable { case named(String, bundle: Bundle) }` — `Bundle` is a non-`Sendable` reference type. Compiler accepts it; it's a lie.

**Rule:** Sendable enums require every associated-value type to be Sendable. For reference types, store the IDENTIFIER (String) and resolve at point-of-use.

**Trap:** `CheckedContinuation` resumed by a multi-fire delegate. SCStream's `didOutputSampleBuffer` fires on every frame; `stopCapture()` is async; the second frame resumes the same continuation → fatal `SWIFT TASK CONTINUATION MISUSE`.

**Rule:** Guard the resume call with `NSLock` + `didResume` flag. Do the resource teardown (stopCapture, removeStreamOutput) in the SAME guarded block. See `OneShotStream.finish(returning:)` / `finish(throwing:)`.

**Rule:** Any framework that uses xxxxOutput-delegate callbacks (AVFoundation, Network framework, Core Bluetooth) inherits this multi-fire shape. Apply the same continuation guard.

Detail: [[Footgun — Sendable Lies in Public Types]]

## Date / timezone discipline

**Trap:** `DateFormatter` without explicit `timeZone` uses `TimeZone.current`. Logs collected on a device in Tokyo and read on a server in UTC appear nine hours apart; tests fail when the CI runner's timezone differs from the developer's.

**Rule:** Pin every internal-use formatter to UTC: `formatter.timeZone = TimeZone(identifier: "UTC")`. Append an explicit `Z` to formatted strings so the reader can't misread.

**Rule:** Always set `formatter.locale = Locale(identifier: "en_US_POSIX")` for any internal date parser/printer. Without it, day-name or month-name formatters crash on Persian / Hebrew system locales.

**Trap:** Parse `Retry-After` only as IMF-fixdate. RFC 7231 §7.1.1.1 requires accepting RFC 850 and asctime forms; servers do send them.

**Rule:** `RateLimitBackoff.parseRetryAfter` tries delta-seconds first, then walks an array of three formatters (IMF-fixdate, RFC 850, asctime).

## Wire format hygiene

**Trap:** Ship redundant derivable state on the wire. `kind` and `labels` both in the body when labels already encode kind. UA in header AND in body. Etc.

**Rule:** Pick one source of truth and document it. UA comes from the HTTP header; relay reads `request.headers["user-agent"]`. Labels encode kind; the relay maps if it needs to.

**Trap:** Two unrelated endpoints share a `currentSchemaVersion` constant. Bumping `/report` silently bumps `/my-issues` even though that endpoint's shape didn't change.

**Rule:** Each endpoint request type owns its own `static let currentSchemaVersion`. Bump them independently.

**Trap:** Configure `JSONEncoder.dateEncodingStrategy = .iso8601` and `JSONDecoder.dateDecodingStrategy = .iso8601`, then type all date fields as `String` and parse manually. The strategy is dead code that misleads the next reader.

**Rule:** If you don't type any DTO field as `Date`, drop the strategy. If you do, drop the manual `parseISO8601` helper. Don't run both.

**Trap:** Submit labels; never check whether they actually stuck. GitHub silently drops labels for tokens without push access (see [[Footgun — Labels and Assignees Silently Dropped]]). "My Issues" correlation that filters on label then returns zero results.

**Rule:** Relay echoes `appliedLabels` in the response. SDK compares against requested and surfaces missing ones via `SubmittedIssue.missingLabels`. Treat `nil` (older relays) as "unknown".

## Test isolation

**Trap:** `nonisolated(unsafe) static var handlers: [URL: ...]` mutated by every test's setUp/tearDown, read by URLSession's internal queue. `swift test --parallel` (or Xcode's default test runner) races on the dictionary.

**Rule:** Wrap shared mock state in a lock-guarded proxy. See `MockURLProtocol.HandlersProxy` for the pattern. Tests still write `MockURLProtocol.handlers[url] = ...` — the lock is transparent.

**Trap:** Test mutates process-wide static state (`GitTickets._configuration`) and never resets it. Later tests inherit the configuration; order-dependent failures sneak in.

**Rule:** Add an internal `_resetForTesting()` hook on any type with process-wide state. Call it from `tearDown`. See `GitTickets._resetConfigurationForTesting`.

**Rule:** Per-test scratch directories use `UUID().uuidString` in the path so parallel runs don't collide. Same for per-test Keychain services. See `KeychainTests.setUp` and `SubmissionCacheTests.setUp`.

## Robust input parsing

**Trap:** `Data(base64Encoded:)` with default options rejects whitespace. A trailing newline from `vercel env pull` or 1Password copy silently returns `nil`; the host chases a phantom secret-mismatch bug.

**Rule:** Trim whitespace and use `.ignoreUnknownCharacters`. Apply the same tolerance to the hex variant. See `SharedSecret.init?(base64:)` / `init?(hex:)`.

**Rule:** When an init takes user-pasted secrets / tokens / config, assume the source mangled whitespace, case, and prefix tokens (`0x`, `Bearer`). Strip aggressively at the boundary.

**Trap:** Hardcoded 5 MB byte limit thrown from a 413 response regardless of the relay's actual configured limit. Operators that raise the limit ship clients that lie about the cap.

**Rule:** Decode the relay's error envelope on 413 and surface the server-reported `byteLimit` if present. Fall back to the SDK default constant only when the envelope is absent.

## iOS multi-window screenshot

**Trap:** `connectedScenes.flatMap(\.windows).first(where: \.isKeyWindow)` enumerates scenes in arbitrary order. iPad Split View: backgrounded Scene A still has `isKeyWindow == true` cached on one of its windows; the screenshot captures the wrong app surface.

**Rule:** Filter scenes by `activationState == .foregroundActive` first, then fall back to `.foregroundInactive`, then fall back to any-scene key window. See `ScreenshotCapture+iOS.activeKeyWindow()`.

## OSLog access

**Trap:** Errors from `OSLogStore(scope:)` silently swallowed → `recentEntries` returns `[]`. Indistinguishable from "no entries in window"; developer triaging never realizes OSLog access failed on the customer's device.

**Rule:** Pass the `GitTicketsLogger?` down to `OSLogTailer.recentEntries` and call `logger?.log(.warning, ...)` on the catch path. Hosts that wired up a logger see the failure.

**Rule:** When the SDK has a public `GitTicketsLogger` protocol, propagate it through every layer where a best-effort failure could otherwise be invisible. Cache writes, OSLog reads, file permission changes — all candidates.

## How to use this page

- New PR that touches networking / signing → re-read the HMAC and Networking sections, plus their footguns.
- New PR that touches the issue body or any caller-controlled string → re-read Markdown and Multipart.
- New PR that introduces concurrent state → re-read Swift concurrency.
- New PR that touches storage → re-read SQLite and Keychain.

Add a new section here when a code review surfaces a class of bug we want to remember. Each section should pair a concrete trap with the concrete rule that prevents recurrence — abstract advice doesn't survive contact with the next reviewer.
