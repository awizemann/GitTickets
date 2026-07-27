---
id: t-56dc81bf
title: v2.1.0 P2: SharedSecret from Info.plist
status: done
added: 2026-07-26
priority: high
---

## Description

ShabuBox ask #2. Additive failable initializer sourcing the relay shared secret from the app bundle's Info.plist, so adopters can feed it from a gitignored xcconfig instead of committing a literal. Owns AuthMode.swift. Must not imply security it does not provide.

## Plan

Base: release/v2.1.0 off v2.0.0 (a491180). Owns Sources/GitTickets/PublicAPI/AuthMode.swift and its tests. Parallel with P1 and P4.

API:
```
extension SharedSecret {
    public enum Encoding: Sendable { case hex, base64 }
    public init?(infoPlistKey: String, encoding: Encoding, bundle: Bundle = .main)
}
```

THREE NON-OBVIOUS CONSTRAINTS:

1. `encoding` MUST be explicit — no default, no sniffing. SharedSecret already has init?(base64:) AND init?(hex:), and a string like "abcdef" is valid in BOTH. Auto-detecting would silently derive the wrong key and surface as unexplainable HMAC signature failures at the relay. Reuse the existing init?(hex:)/init?(base64:) rather than reimplementing the decode — they already handle the whitespace/trailing-newline cases that env tooling introduces.

2. DO NOT add an AuthMode case. The request floated `.relay(url:sharedSecretInfoPlistKey:)`, but AuthMode is a public enum and adding a case is SOURCE-BREAKING for any adopter with an exhaustive switch over it — which this release must not do. The initializer is sufficient: `.relay(url: u, sharedSecret: SharedSecret(infoPlistKey: "GTSecret", encoding: .hex)!)`. Document the recommended guard/precondition pattern for the failable result, including what a nil actually means (key absent, or present but not decodable in the stated encoding — distinguish these in the doc).

3. DO NOT implement environment-variable sourcing, despite the request mentioning it. A shipped .app launched from Finder has no useful environment; env vars only arrive under Xcode or a terminal. Shipping that path would invite adopters to build a config mechanism that silently fails for their real users. Say so in the doc comment so the omission reads as deliberate.

DOC HONESTY REQUIREMENT: state plainly that Info.plist is PLAINTEXT in the shipped bundle and trivially readable (`plutil -p MyApp.app/Contents/Info.plist`). This keeps the secret out of GIT, not out of an attacker's hands; its purpose is to gate casual relay abuse, not to guard anything. An API named for Info.plist secrets invites false confidence — the doc must actively defeat that. Cross-reference docs/threat-model.md if it already covers the shipped-secret reasoning.

VERIFY: unit tests covering present-and-valid (both encodings), key absent, present-but-wrong-encoding, and empty/whitespace value. Test against a real Bundle — inject a test bundle rather than mocking, and if the test bundle cannot carry Info.plist keys under SwiftPM, say so and explain how you tested instead. swift build 0 warnings, swift test green. Then a fresh-eyes audit: could a misconfiguration produce a silently WRONG key rather than nil? That is the dangerous failure mode.

## Artifacts

DONE 2026-07-26. Commit ef74e22 on worktree-agent-a30eaca36ce92e242 (parent a491180, base verified correct — not stale). 2 files, +490/-7: AuthMode.swift plus a NEW test file Tests/GitTicketsTests/Auth/SharedSecretInfoPlistTests.swift (27 tests, deliberately a separate file to avoid conflicts with the parallel agents).

DELIVERED AS SPECIFIED: SharedSecret.Encoding (.hex/.base64) + init?(infoPlistKey:encoding:bundle: = .main). No AuthMode case added. No env-var path. `encoding` mandatory, nothing sniffed. Decoding delegates to the existing init?(hex:)/init?(base64:).

GOOD DEVIATION, ACCEPTED: reads `bundle.infoDictionary?[key]` rather than `object(forInfoDictionaryKey:)`. The latter consults InfoPlist.strings and can return a LOCALIZED OVERRIDE of the key — i.e. a path to a silently different signing key, which is the exact failure class this phase exists to prevent. Good catch.

*** THE AGENT FOUND THREE PRE-EXISTING SECURITY DEFECTS IN SHIPPED CODE. ALL THREE CONFIRMED BY THE ORCHESTRATOR against the real v2.0.0 tag from the public remote (not against the agent's branch, not by reading the diff): ***
1. SharedSecret(hex: "") / "   " / "0x" -> NON-NIL 0-BYTE key. Zero digits satisfies the even-length check. init?(base64:) already rejected empty; hex did not.
2. SharedSecret(hex: "+1+1") -> bytes 01 01, because UInt8(_:radix:) honours a leading + sign. Confirmed at the stdlib level: UInt8("+1", radix: 16) == 1.
3. SharedSecret(base64: "====") -> 1-BYTE 0x00 key. Data(base64Encoded: "====") decodes padding-only input to one zero byte, which is non-empty and slipped past the !data.isEmpty guard.

REALISTIC HARM (stated precisely, not inflated): these do not leak a secret. They let a misconfiguration produce a degenerate, publicly-guessable HMAC key that FAILS SILENTLY instead of loudly. If only the app side is degenerate, signatures mismatch and submission simply breaks (annoying, safe). The dangerous case is BOTH sides degenerate — then the relay appears to work while providing zero authentication, so the shared secret stops gating relay abuse at all.
WHY IT MATTERS NOW: this phase's whole purpose is sourcing the secret from EXTERNAL config, which makes an empty or unsubstituted value far more reachable than a hand-typed literal ever was (missing xcconfig substitution, empty Info.plist value). The defect and the feature are coupled; fixing it here is correct, not scope creep.

FIXES VERIFIED INDEPENDENTLY by the orchestrator via a probe consumer built against the agent's branch: all five degenerate inputs now return nil; NO over-rejection (0b11 -> 0b 11, 0xdeadbeef -> de ad be ef, 3q2+7w== -> de ad be ef); and no sniffing (deadbeef gives 4 bytes as hex, 6 bytes as base64).

DECISION (orchestrator): KEEP the fixes despite being a behavior change to two existing public initializers in a minor. Every newly-rejected input was never a legitimate secret, and the only configuration that previously "worked" is one with zero security on both ends — worth breaking loudly. MUST be called out prominently in the CHANGELOG as a security fix, noting the defect exists in v1.x and v2.0.0 as shipped.

"FLAKY RUN" RESOLVED — NOT ENVIRONMENTAL, NOT A MYSTERY. The agent's first swift test reported 6 failures it could not reproduce in 7 later runs, and attributed it to sandbox/XPC noise. It is the known first-run snapshot-baseline recording: a fresh worktree has no gitignored __Snapshots__ PNGs, swift-snapshot-testing reports a fresh recording as a FAILURE, and there are exactly 6 snapshot tests. The orchestrator proved this earlier in the session on a pristine clone ("Executed 6 tests, with 6 failures" + "No reference was found on disk"), and confirmed the P2 worktree now holds exactly 6 PNGs. The CoreData NSXPCConnection noise is unrelated and appears on passing runs too. See operations/footgun-xcodebuild-test-does-not-forward-env-to-xctest.

ALSO CORRECTED: init?(base64:)'s doc claimed it "accepts embedded whitespace" — false (Data(base64Encoded: "de ad") is nil). Behavior was right, docstring was wrong.

FOLLOW-UPS, NOT DONE: (a) pre-existing test test_sharedSecretBase64ToleratesEmbeddedWhitespace (GitTicketsTests.swift:82) is misnamed — it tests SURROUNDING whitespace; left alone to keep the diff conflict-free, worth renaming later. (b) No minimum key-length or entropy check: "0000000000000000" decodes to 8 zero bytes, legitimately decoded but cryptographically terrible. Rejecting short/low-entropy secrets would break existing adopters — a major-version policy call, correctly out of scope here.

