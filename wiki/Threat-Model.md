---
title: Threat-Model
type: note
permalink: gittickets-wiki/threat-model
---

# Threat Model

What the GitTickets system protects against, what it doesn't, and where the trust boundaries are.

## Trust boundaries

```
[ End-user device ] ──HMAC──▶ [ Relay (developer-owned) ] ──App token──▶ [ github.com ]
        Untrusted                       Trusted                                Trusted
```

- **End-user device is untrusted.** The HMAC shared secret IS in the app binary and IS extractable. Treat it as obfuscation, not security.
- **Relay is the trust boundary.** It holds the GitHub App private key. Everything sensitive must live here. Mint installation tokens on-demand, cache for 50 minutes, never log.
- **GitHub is trusted.** Outside our scope.

## In scope

- Preventing random-internet abuse of the relay (per-IP rate limit, HMAC signature, minimum body length).
- Preventing token leakage from the relay (env-var-only secrets, no logging of tokens, GitHub App scoped to `Issues: write` on ONE repo).
- Preventing replay of intercepted requests (`X-GitTickets-Timestamp` header with a 5-minute window).
- Preventing PII leakage from diagnostics (redaction pipeline — email, IP, bearer-token regexes — runs before display AND before send).
- Preventing public exposure of private content the user didn't expect (mandatory privacy banner above the form, copy keyed off `RepoVisibility`).

## Out of scope

- **Determined attackers extracting the HMAC shared secret.** It's in the binary. Recommend rotation on major versions; for higher security adopt App Attest (iOS) / DeviceCheck / Play Integrity attestation tokens in v2.
- **End-user impersonation.** GitTickets reports are anonymous by design. If you need verified identity, use Device Flow (the issue is then authored by the user's GitHub account).
- **Spam from a single legitimate-looking actor.** Rate-limit catches floods; targeted single-user spam is the maintainer's moderation problem (close, lock, block on github.com).
- **GitHub spam heuristics catching the App.** Relay enforces a 50-char minimum body, debounces identical bodies within 60s, and rejects URL-only / single-word submissions. This reduces but doesn't eliminate risk.

## Why we don't ship PAT-in-binary mode

Even as an "easy starter" mode for friends-and-family rollout. Three reasons:

1. **Extraction is trivial.** `strings` against the IPA reveals the token. A single jailbroken device leaks every user's submission credential.
2. **Rotation breaks every shipped build.** Once leaked, the only fix is to ship a new app version with a new token. Existing installs can't submit.
3. **Blast radius is the entire PAT scope.** PATs can't be scoped to "issues only on one repo" with the same precision as a GitHub App.

If a developer insists on PAT for a private internal tool with three users, they can use Device Flow with their own account. There's no GitTickets API for embedded PATs.

## Vercel Blob attachment lifetime

Vercel Blob free-tier URLs are time-limited (90 days). After expiry, attached images 404 from the issue. Document loudly in `relay/vercel/README.md`. Recommend Cloudflare R2 (configurable public bucket) for permanence, or v1.1 contents-API write into a sibling `*-attachments` repo.

## App Store / privacy review

A `PrivacyInfo.xcprivacy` ships with the package (declared as a target resource via `Package.swift`'s `.copy(...)`), declaring:

- `NSPrivacyTracking: false`, no tracking domains.
- Three collected data types — `OtherDiagnosticData` (the diagnostics blob), `DeviceID` (the per-install UUID from `DeviceIdentity`), `PhotosorVideos` (user-attached images). All `Linked=false / Tracking=false / Purpose=AppFunctionality`.
- One required-reasons API: `DiskSpace` reason `85F4.1` (for `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])` in `DiagnosticsCollector.freeDiskDescription`).

The PR 18 audit dropped the speculative `CrashData` / `PerformanceData` / `UserDefaults` claims from the initial draft after `grep` confirmed zero use. Adopters must declare these in their app's privacy manifest too. `docs/privacy.md` provides reviewer-facing paste copy + the manifest-merge semantics.

## Reporting vulnerabilities

`SECURITY.md` at repo root has the disclosure process. SDK and relay templates are both in scope.

## Class-level pitfalls surfaced by code review

Specific traps the PR 1–8 code review caught and the conventions that now prevent recurrence. Each entry links to a footgun note with the full write-up.

- **HMAC re-signing on retry** — sign per attempt, not before the retry loop. Stale timestamps surface transient 5xx as `signatureMismatch`. [[Footgun — HMAC Signature Stale on Retry]]
- **Non-idempotent POST retries** — never retry POSTs on transport errors without an idempotency key + cache lookup. [[Footgun — Retry Non-Idempotent POST Without Idempotency Key]]
- **Redactor over-match** — naive IPv4/IPv6 regexes match version strings and clock timestamps. Bearer redaction must run first so embedded IPs don't corrupt the token charset. [[Footgun — Redactor Regexes Over-Match]]
- **Multipart header injection** — sanitize filename, allowlist + CRLF-reject MIME. [[Footgun — Multipart Header Injection via Filename and MIME]]
- **Keychain platform defaults** — set `kSecAttrSynchronizable: false` explicitly; namespace service by host bundle. [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]]
- **Sendable lies** — `nonisolated(unsafe) static var` is not atomic; Sendable enums need Sendable associated values; CheckedContinuation guards. [[Footgun — Sendable Lies in Public Types]]
- **Markdown injection** — dynamic fence length, escape URLs and link text. [[Footgun — Markdown Injection in GitHub Issue Body]]
- **SQLite file permissions** — chmod 0600 after open on non-sandboxed macOS. [[Footgun — SQLite Cache File Default Permissions]]

The consolidated cheat-sheet view is [[Patterns and Gotchas]] in the wiki.

---
_Last updated: 2026-06-06 — privacy-manifest declarations refreshed against the shipped `PrivacyInfo.xcprivacy`_
