---
title: Footgun — Redactor Regexes Over-Match
type: note
permalink: gittickets/footguns/footgun-redactor-regexes-over-match
tags:
- footgun
- privacy
- diagnostics
- redaction
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

Naive PII regexes match more than the thing they're named after. Three specific landmines we hit:

1. **IPv4 `\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b`** matches four-part version strings like `1.0.0.123` in `App: MyApp 1.0.0 (1.0.0.123)` — the build number (the single most useful triage field) gets rewritten to `[ip redacted]`.
2. **IPv6 `\b[A-F0-9]{0,4}(?::[A-F0-9]{0,4}){2,7}\b`** (case-insensitive) matches `HH:MM:SS` clock timestamps because decimal digits are a subset of hex. Every OSLog line's leading timestamp gets stripped. Worse: the same pattern fails to match `::1` loopback because `\b` requires a word-char on at least one side of the leading `:`.
3. **Redactor order matters.** If IPv4 redactor runs before bearer redactor, an IPv4-shaped substring inside a Bearer token is rewritten to `[ip redacted]`, which contains characters (`[`, space, `]`) outside the bearer charset `[A-Z0-9._\-/+]`. The bearer regex then fails to match the corrupted token, and the leftover JWT halves leak.

Discovered in code review of PR 5 + PR 7.

## Observations

- [rule] IPv4 redactor uses strict octet validation (each octet 0–255) AND excludes paren / dot / digit context on either side: `(?<![0-9.(])...(?![0-9.)])`. Won't match `(1.0.0.123)` because the open-paren lookbehind rejects it. #privacy
- [rule] IPv6 redactor requires the match contain either at least one hex letter OR a `::` zero-compression marker: `(?=[A-F0-9:]*(?:[A-F]|::))`. Excludes all-decimal clock-like strings; accepts `::1` and standard forms. Uses `(?<![A-F0-9:])` / `(?![A-F0-9:])` instead of `\b` so leading-`:` addresses work. #privacy
- [rule] Default redactor order is `[.bearerToken, .email, .ipv4, .ipv6]` — bearer first so embedded IPs in tokens don't break the token-charset match. #privacy
- [rule] When adding any new redactor, write a fixture test that includes the REAL diagnostics blob shape (timestamps, version strings, file paths, log lines) — abstract regex tests miss the over-match cases. See `RedactionPipelineTests.test_realisticBlobWithEverything` for the pattern. #testing
- [rule] Limitation: even strict IPv4 octet-valid regex cannot syntactically distinguish a four-part version inside parens from a real IPv4 inside parens. The paren-context exclusion is a heuristic that helps `App: ... (1.0.0.123)` but not the (rarer) case `from (192.168.1.1)`. Document the asymmetry; we err on the side of preserving the triage field. #privacy
- [verification] Regression tests: `test_ipv4DoesNotMatchVersionStringInParens`, `test_ipv6DoesNotMatchClockTimestamps`, `test_ipv6MatchesLoopbackAndStandardForms`, `test_defaultRedactorOrderProtectsBearerWithEmbeddedIPv4`. #testing

## Relations

- prevents_recurrence_of "build number redacted as IP"
- prevents_recurrence_of "clock timestamp redacted as IPv6"
- prevents_recurrence_of "bearer token leaking after IP redaction corrupted it"
