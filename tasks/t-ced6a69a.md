---
id: t-ced6a69a
title: v2.0.0 P4: version metadata, CHANGELOG, docs
status: done
added: 2026-07-25
priority: high
---

## Description

Phase 4 of v2.0.0, sequential after P1-P3 land. Bump sdkVersion, write the 2.0.0 CHANGELOG entry, and correct the compatibility claims across README and docs — including a correction note against the wrong 1.1.0 entry. This is the phase that fixes the actual root cause of this whole exercise: an unverified toolchain claim.

## Plan

Runs AFTER P1/P2/P3 are merged onto release/v2.0.0, in the main working tree (no worktree).

FILE OWNERSHIP: CHANGELOG.md, README.md, docs/**, Sources/GitTickets/Networking/UserAgent.swift (sdkVersion line only).

WORK:
1. UserAgent.sdkVersion "1.1.0" -> "2.0.0" (and the doc-comment example alongside it).
2. CHANGELOG [2.0.0] entry. Breaking: platform floor macOS 13 -> 14, iOS 16 -> 18. Changed: ScreenCaptureKit capture now uses SCScreenshotManager; redundant availability annotations removed; SwiftUI modernization; CI reworked. State clearly that dropping platforms is why this is a major version.
3. STATE THE TWO FLOORS SEPARATELY — this is the whole point. Toolchain floor (what compiles the package) and runtime floor (what runs it) are different things, and merging them into one sentence is exactly how v1.1.0 shipped a false claim.
4. Correct the v1.1.0 entry: add a note that its stated "minimum toolchain Swift 6.0 (Xcode 16+)" was wrong — v1.1.0 does not compile on Xcode 16.2 because of the ScreenCaptureKit Task isolation error, fixed in 2.0.0. Do not rewrite history, annotate it.
5. Toolchain claim for 2.0.0: only claim what CI actually verifies once P3's workflow has run. If unverified at write time, say "developed and tested on Xcode <version>" rather than inventing a floor. NEVER state a minimum you have not built against — that is the bug we are fixing.
6. README status line and docs/getting-started.md: update the requirements block and the `from: "1.1.0"` example to 2.0.0. Note that consumers pinned upToNextMajorVersion from 1.x will NOT auto-resolve to 2.0.0 and must bump deliberately.
7. Sweep docs/ and Examples for any remaining macOS 13 / iOS 16 references and for stale github.com/alanw placeholders (origin is awizemann; a previous pass flagged these but may not have caught all).

VERIFY: swift build + swift test still green; grep the whole repo for "macOS 13", "iOS 16", "1.1.0", "Xcode 16" and account for every remaining hit.

Then fresh-eyes audit: read the CHANGELOG as an outside adopter on macOS 13 — is it unambiguous that they cannot use this version, and what they should pin instead? Report honestly.

## Artifacts

DONE 2026-07-26. Commit 484b66e on release/v2.0.0. 5 files: CHANGELOG.md, README.md, CONTRIBUTING.md, docs/getting-started.md, UserAgent.swift. No managed tiers committed (verified).

CHANGELOG [2.0.0] is structured so the two floors CANNOT be conflated — a dedicated "Two floors, stated separately" section asserts the runtime floor (enforced by SwiftPM) and deliberately asserts NO minimum toolchain, listing only what was built and run. It also distinguishes structural constraints (swift-tools-version:6.0, and .iOS(.v18) being @available(_PackageDescription 6.0) — verified in the toolchain's PackageDescription.swiftinterface) from measured claims. The [1.1.0] entry carries an in-place correction block naming the false claim, its mechanism, and the fact that it also appeared in the annotated git tag, with the original text preserved unedited beneath.

TWO CATCHES BY THE AGENT WORTH KEEPING:
1. iOS 17 was being silently omitted. The floor jumps 16 -> 18, so iOS 17 apps are excluded TOO — neither the orchestrator nor the plan had stated this. Now explicit in the CHANGELOG, README, and docs.
2. The agent caught itself recreating the original sin at small scale: a first draft said v1.0.0 "builds on a Swift 5.9-era toolchain" — a compatibility claim it had not built. Rewrote it to a declaration-level fact verified from `git show v1.0.0:Package.swift`.

ORCHESTRATOR-ADDED FIXES (escalated by the agent as out of its scope, both accepted):
- CONTRIBUTING.md:21 read "The package builds on macOS 13+ and iOS 16+ (Swift 5.9 toolchain)" — stale since 1.1.0 and outright false. Shipping 2.0.0 with that intact would have put a fresh false compatibility claim in the very release that exists to fix false compatibility claims. Rewritten to state the runtime floor plus what is actually used, with no invented minimum.
- README.md privacy-manifest bullet said "iOS 17+ Privacy Manifest" — not false (it referenced Apple's requirement threshold) but reads as a support claim now the floor is iOS 18. Changed to "Privacy manifest (PrivacyInfo.xcprivacy) for App Store submission."

FINAL RELEASE-CANDIDATE VERIFICATION at 484b66e, run by the orchestrator on a PRISTINE clone (not agent-claimed):
- swift build --build-tests: 0 warnings
- TEST_RUNNER_CI=true xcodebuild test, platform=macOS: ** TEST SUCCEEDED **, 210 executed / 6 skipped / 0 failures
- xcodebuild generic iOS Simulator: ** BUILD SUCCEEDED **
- git status after a full build+test cycle: 0 stray files
- Public API stability across the ENTIRE release (51b13d9..484b66e): zero removed or added `public`/`open` declarations in Sources/. Confirms the major bump is driven purely by the platform floor, not by API churn.
- End-to-end adopter proof: a fresh consumer package declaring .macOS(.v14) with a path dependency on the release branch COMPILES AND RUNS, exercising Configuration/RepoCoordinate/AuthMode.relay/SharedSecret. Printed "consumed OK: awizemann MyApp public".
- Gap check nobody's phase owned: Examples/ is three standalone .swift files plus a README with no build system and zero stale floor references. Package.resolved is untracked (correct for a library). Only ONE Package.swift exists in the repo.

MINOR OBSERVATION, NOT ACTED ON: the primary public config type is named `Configuration` — unnamespaced and generic for a type adopters import into their own module. The orchestrator fumbled it three times writing the consumer test (guessing `GitTicketsConfiguration`), which is weak evidence the name is unintuitive and a mild collision risk. A rename would be a breaking change, so a major version is the cheapest moment for it — but it is NOT part of the agreed scope and should not delay this tag. Flagged for Alan as a standalone decision.

