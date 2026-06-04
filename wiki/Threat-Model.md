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

A `PrivacyInfo.xcprivacy` ships with the package, declaring:

- `NSPrivacyTracking: false`
- Collected data types: CrashData (the bug body, if user describes a crash), PerformanceData (memory/disk diagnostics), OtherDiagnosticData, DeviceID (our deviceID UUID) — all linked-to-app-functionality, none linked-to-tracking.
- Required-reasons APIs: `DiskSpace` reason `85F4.1`, `UserDefaults` reason `CA92.1`.

Adopters must re-declare these in their app's privacy manifest. `docs/privacy.md` provides reviewer-facing paste copy.

## Reporting vulnerabilities

`SECURITY.md` at repo root has the disclosure process. SDK and relay templates are both in scope.

---
_Last updated: 2026-06-04 — initial threat model_
