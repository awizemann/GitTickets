---
id: t-7a4acd7f
title: v2.1.0 P1: built-in absolute-path redactor + safe ordering
status: done
added: 2026-07-26
priority: high
---

## Description

ShabuBox ask #3. Add a built-in DiagnosticsRedactor for absolute paths (stripping the trailing filename too), position it correctly in the default array so the IP/email redactors cannot truncate it, and document the ordering interaction. Owns Policies.swift + RedactionPipeline.swift. Highest over-match risk in the release.

## Plan

Base: release/v2.1.0 off v2.0.0 (a491180). Owns Sources/GitTickets/PublicAPI/Policies.swift, Sources/GitTickets/Diagnostics/RedactionPipeline.swift, and redaction tests. Runs parallel with P2 (AuthMode) and P4 (UI). P5 (attachment names) waits on this because it also needs Policies.swift.

WHY ORDERING MATTERS — the codebase already hit this exact bug class: Policies.swift:38-40 documents that .bearerToken runs FIRST "so that IPv4/IPv6 redactions inside a token don't corrupt the token's surrounding charset and let the leftover halves leak." A path is the same shape of problem: [ip redacted] and [email redacted] both insert spaces and brackets, truncating an in-flight path match and stranding the filename. There is a memory note on this: footguns/Footgun — Redactor Regexes Over-Match.

API:
- `public static let absolutePath` — replacement "[path redacted]".
- `public static let recommended: [DiagnosticsRedactor] = [.bearerToken, .absolutePath, .email, .ipv4, .ipv6]` so adopters composing custom lists start from a correct base (`redactors: DiagnosticsRedactor.recommended + [mine]`).
- DiagnosticsPolicy's `redactors:` default becomes `DiagnosticsRedactor.recommended`. APPROVED behavior change (Alan): existing adopters on defaults start getting path redaction. Source-compatible; call it out for the CHANGELOG.
- Do NOT auto-reorder a caller-supplied array. The array IS the contract and reordering it trades one surprise for a worse one, plus it would break anyone deliberately relying on bearer-first. Document the interaction instead, on both `redactors:` and DiagnosticsRedactor.

PREFIXES TO COVER: /Users/, ~/, /Volumes/, /private/, /var/, /tmp/, /Applications/, /Library/ — and the trailing filename must go too.

OVER-MATCH HAZARDS (this regex is riskier than any existing one — guard each and test it):
- URLs: https://example.com/library/foo must NOT be partly redacted. Needs a leading boundary that rejects a preceding path/host character.
- Bare `~` in prose or `~=` must not match; require `~/`.
- unsafeRegex applies .caseInsensitive globally, so /users/ and /VAR/ also match — intended, but be deliberate.
- Must NOT swallow the fields that make triage possible.

VERIFY — the memory note's rule is mandatory here: write a fixture test using a REALISTIC diagnostics blob (timestamps, version strings, log lines, paths), not abstract regex cases. That discipline is what caught IPv4-matches-build-number and IPv6-matches-clock-timestamp. Follow the existing pattern in RedactionPipelineTests.test_realisticBlobWithEverything.
Required assertions:
1. /Users/alan/Library/Containers/com.shabubox.app/Data/Documents/SomeTaxReturn2024.pdf is redacted ENTIRELY — path, account name, and filename.
2. App version, macOS version, hardware model and locale all SURVIVE.
3. An ordering regression test mirroring the existing test_defaultRedactorOrderProtectsBearerWithEmbeddedIPv4, but proving an IP embedded in a path cannot truncate the path match and strand the filename.
4. A URL containing /library/ or /var/ is not corrupted.
Then: swift build 0 warnings, swift test all green (210 baseline + your new tests), and a fresh-eyes adversarial re-read hunting for over-match.

## Artifacts

DONE 2026-07-26. Commit 28d8388 on worktree-agent-a6ee39886b2f80b81, merged to release/v2.1.0. 4 files, +586/-5. 24 new tests; combined tree after merging P1+P2 is 261 tests, 0 failures, 0 build warnings (verified by orchestrator).

SHIPPED: `.absolutePath` redactor (replacement "[path redacted]"), `DiagnosticsRedactor.recommended = [.bearerToken, .absolutePath, .email, .ipv4, .ipv6]`, and DiagnosticsPolicy's `redactors:` default now points at it. Caller-supplied arrays are still applied VERBATIM — no reordering magic — and there is a test asserting a deliberately-bad caller order is honored, plus a note in RedactionPipeline's docs so a future maintainer does not "helpfully" add sorting.

ORCHESTRATOR-VERIFIED BEHAVIOR (probe consumer built against the branch, running the real default pipeline — not agent-claimed):
- ACCEPTANCE MET: /Users/alan/Library/Containers/com.shabubox.app/Data/Documents/SomeTaxReturn2024.pdf -> "[path redacted]" entirely. Path, account name, filename all gone.
- Triage fields survive: "App: ShabuBox 2.1.0 (2.1.0.42) | macOS 26.0.0 | Mac16,7 | en_US" untouched — including the four-part build number the IPv4 redactor is documented to leave alone.
- URLs intact: https://cdn.example.com/var/assets/x and https://ex.com/library/y both unmodified.
- ORDERING FIXED: an IP inside a path (/Users/ana/logs/192.168.1.5/Taxes2024.pdf) redacts as one unit — the truncation ShabuBox reported is gone. Same for an email inside a path (/Users/bob@corp.com/Documents/W2.pdf).
- Unicode filenames fully redacted (確定申告2024.pdf). The agent included \p{M} deliberately because APFS stores names decomposed, so "Café.pdf" is Cafe + combining acute and an ASCII-only class would stop mid-filename and publish the document name.
- ~/ paths redacted; bare tilde prose ("approx ~5", "5~10", "report~") untouched.
- /System/ paths and source locations (Main.swift:42:17) preserved for triage.

*** KNOWN GAP — SPACES TERMINATE THE MATCH. Flag to ShabuBox. ***
"open /Users/ana/Documents/Tax Return 2024.pdf failed" -> "open [path redacted] Return 2024.pdf failed". The account name always goes, but a filename containing spaces PARTIALLY SURVIVES. This matters because ShabuBox's own motivating examples have spaces ("Tax Return 2024.png", "Mercy Hospital discharge.pdf"). The agent's tradeoff is nevertheless correct: allowing spaces lets the match run off into the surrounding log message and eat triage text, which is worse. So item 3 is a documented FLOOR, not total coverage.
MITIGATION GUIDANCE FOR SHABUBOX: add a custom redactor matching their own container path including spaces, and place it BEFORE .absolutePath — i.e. construct the array manually as [.bearerToken, theirs, .absolutePath, .email, .ipv4, .ipv6]. Do NOT use `DiagnosticsRedactor.recommended + [theirs]` for this case: append puts theirs LAST, where .absolutePath has already truncated the match. The append pattern is only correct for redactors that do not need to win against a built-in — P5 must say this explicitly in the docs.

OTHER DOCUMENTED LIMITATIONS (all pinned by tests so they stay visible rather than becoming folklore):
- Backslash-escaped separators are missed: {"path":"\/Users\/ana\/Taxes.pdf"} is untouched. Lower risk than it sounds — Swift's JSONEncoder does not escape forward slashes, so the common JSON form is redacted; the \/ form comes from some JS/PHP encoders.
- System prefixes (/System/, /usr/, /opt/, /bin/, /etc/) deliberately not covered: no user identity, and keeping them readable preserves stack-trace triage value.
- ~/ will match /~/ inside a URL; accepted to keep file:///Users/... coverage.
- Case-insensitivity kept on purpose — Apple filesystems are case-insensitive, so /users/ is the same file and the same leak.
- Markdown-link adjacency: "/Users/ana/x.pdf(errno)" becomes "[path redacted](errno)", which is [text](url) syntax. Inert because IssueBodyBuilder always fences diagnostics and redaction runs before fencing, and it is a pre-existing property of the "[... redacted]" style shared with [ip redacted]. Only an adopter who pre-collects via DiagnosticsCollector.collect and renders it unfenced could see it.

RIGOR NOTE: the agent validated candidate patterns in a scratch harness, then confirmed the ACTUALLY SHIPPED pattern by dumping absolutePath.regex.pattern from the built module and re-running its adversarial corpus through that, rather than trusting a copy. No catastrophic backtracking (32 KB adversarial input in 0.3 ms).

SCOPE NOTE: touched one file outside its stated ownership — Tests/GitTicketsTests/GitTicketsTests.swift:100, a single assertion listing the default redactor names, which the approved default change necessarily broke. One line, correctly flagged, and it did not conflict with P2. Accepted.

BEHAVIOR CHANGE FOR THE CHANGELOG: adopters on defaults will start seeing absolute paths redacted in diagnostics. Source-compatible, nothing removed, opt-out is passing an explicit redactors array.

FLAKE MISDIAGNOSED AGAIN: this agent also hit the first-run 6-failure snapshot recording and attributed it to Keychain/CoreData state after failing to reproduce it. Notably its cold-.build reruns still passed, which CONFIRMS the snapshot explanation — deleting .build does not remove the recorded PNGs under Tests/. Two of two agents misdiagnosed this; future briefs must pre-empt it explicitly.

