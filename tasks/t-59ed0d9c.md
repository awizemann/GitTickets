---
id: t-59ed0d9c
title: v2.0.0 P3: make CI meaningful (runner, destinations, snapshots)
status: done
added: 2026-07-25
priority: high
---

## Description

Phase 3 of v2.0.0. Rebuild .github/workflows/swift.yml so a green run actually means something at the macOS 14 / iOS 18 floor, and stop snapshot tests from passing vacuously on CI. Owns the workflow, SnapshotTests.swift, and .gitignore only. Isolated worktree, parallel with P1 and P2.

## Plan

Base: branch release/v2.0.0 at ab63920.

FILE OWNERSHIP (strict):
- OWNS: .github/workflows/swift.yml, Tests/GitTicketsTests/UI/SwiftUI/SnapshotTests.swift, .gitignore, and the stale comment at Package.swift:34-38 (see item 4).
- MUST NOT TOUCH: Sources/ (P1 and P2 own it), CHANGELOG/README/docs (P4).

CURRENT STATE, GROUNDED:
- runs-on: macos-14, whose newest Xcode is 16.2 (Swift 6.0). Matrix destinations are "platform=macOS" and "platform=iOS Simulator,name=iPhone 15,OS=17.5".
- The workflow has NEVER gone green. In the most recent run (29180361732) the iOS job PASSED and only the macOS job failed, solely on the ScreenCaptureKit compile error that P2 deletes.
- The iPhone 15 / OS=17.5 destination is now incompatible with an iOS 18 deployment floor — it must change regardless.
- Do NOT treat NSURLErrorDomain -1009 as a failure: it is logged inside HTTPClientTests test_transportErrorRetriesThenThrows, which passes (slowly, ~26s). Leave it alone.

WORK:
1. Bump the runner to an image whose Xcode can build a Swift 6 package and that ships an iOS 18+ simulator runtime (macos-15 or newer). Verify the image actually provides what you claim — do not guess at available Xcode or simulator versions; check GitHub's runner-images documentation.
2. Update destinations to match the new floor. Prefer a generic destination for the build step; a concrete simulator is only needed for the test step.
3. Reconsider `xcode-version: latest-stable`. Pin deliberately or document why floating is wanted — floating silently changed compiler behavior once already and that is exactly how the Swift 6.0 breakage went unseen.
4. Snapshots: they are gitignored (.gitignore:33 `__Snapshots__/`) with ZERO baselines tracked, so on CI they record fresh and pass vacuously — false confidence. Make them skip explicitly on CI (env var guard, e.g. honoring CI=true, or an XCTSkip) so they stay a local-only pre-release check and CI green becomes meaningful. ALSO: the comment at Package.swift:35 claims baselines are "checked in next to their tests" — that is false. Correct it.
5. Keep the iOS Simulator keychain-entitlement footgun in mind (there is a memory note on it); if it resurfaces on the new image, skip those tests on CI with a comment pointing at the note rather than weakening the production code.

VERIFY — this is the hard part, be rigorous and honest:
- You CANNOT run GitHub Actions locally. Do not claim CI is green.
- DO validate the workflow YAML parses and the destination strings are well-formed.
- DO run the equivalent commands locally where possible and report results: `xcodebuild -scheme GitTickets -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation build` succeeds today; local sim runtimes are iOS 26.2/26.5/27.0 (no iOS 18 runtime installed locally, so a concrete iOS 18 destination cannot be tested here — say so).
- DO verify the snapshot skip works by running `swift test` with and without the CI env var set and reporting the test counts in each case.

Then a fresh-eyes adversarial self-audit: does the workflow actually fail when the code is broken? Or have you made it green-by-avoidance (skipping so much that it proves nothing)? Say which of the 210 tests still run on CI after your change, and defend that number. Report honestly.

Commit in the worktree and report branch + SHA + diffstat.

## Artifacts

DONE 2026-07-25. Commit f32bffa on worktree-agent-ad251dc252f539cc2. 5 files, +121/-11: .github/workflows/swift.yml, .gitignore, Package.swift (comment only — platforms verified intact at .v14/.v18), SnapshotTests.swift, __Snapshots__/.gitkeep.

*** THIS PHASE CORRECTED THE ORCHESTRATOR ON A LOAD-BEARING FACT ***
I had characterized the snapshot tests as "recording fresh and passing vacuously on CI — false confidence." That is WRONG, and the wrong version was used in the option text Alan chose from. Reality: swift-snapshot-testing reports a fresh recording as a FAILURE ("No reference was found on disk. Automatically recorded snapshot"). On a baseline-free checkout all 6 FAIL. Independently verified by the orchestrator on a pristine clone: `Executed 6 tests, with 6 failures`, and via xcodebuild: `** TEST FAILED **`.
Consequence: the macOS CI job had TWO independent blockers, not one (the ScreenCaptureKit compile error AND 6 deterministic snapshot failures). P3 was therefore load-bearing for first-green, not hygiene. Alan's choice to skip on CI remains correct — more clearly correct, since the alternative was permanent red.

BEST FIND — a fix that would have silently done nothing: `xcodebuild test` does NOT forward the job environment into the XCTest process, so the `CI=true` that GitHub sets is invisible to tests. `swift test` inherits it; `xcodebuild test` does not — and CI uses xcodebuild. Verified: `CI=true xcodebuild test` -> 6 failures, 0 skipped, exit 65. The fix is `TEST_RUNNER_CI: 'true'` (xcodebuild strips the prefix and injects CI=true). Had the agent verified only with `swift test`, it would have shipped a no-op and reported success.

CONFIG DECISIONS: runs-on macos-15 — macos-14 is deprecated (newest Xcode 16.2) and macos-15 is the ONLY current image still shipping an iOS 18.x runtime (18.5/18.6); macos-26 ships iOS 26.x only, so it cannot test AT the iOS 18 floor. Xcode pinned to '26.3' (quoted so YAML doesn't read it as a float) replacing `latest-stable` — floating is precisely how the Swift 6.0 breakage went unnoticed with no commit to blame. Matrix split into build-destination (generic, no simulator boot) and test-destination (concrete iPhone 16 / OS=18.6).

GITIGNORE SUBTLETY the agent caught: the naive `__Snapshots__/*` plus negation SILENTLY FAILED — a pattern containing a slash is anchored to the repo root, so it stopped ignoring the real nested baselines. Needed `**/`. Verified with `git add --dry-run`.

ORCHESTRATOR VERIFICATION OF THE MERGED TREE (none of this was agent-claimed):
- Mutation-test safety: the agent mutated RedactionPipeline.redact to a no-op mid-run, was blocked by the permission classifier, and reverted. VERIFIED CLEAN — the RedactionPipeline blob at f32bffa is byte-identical to base (38ce0860fa4dbdfc19f69e9e0c2afa12c2021b95) and the commit touches ZERO files under Sources/.
- Pristine clone + TEST_RUNNER_CI=true xcodebuild test -> `** TEST SUCCEEDED **`, 210 executed / 6 skipped / 0 failures, and 0 PNGs on disk afterward, proving the skip precedes recording. git status spotless.
- Same pristine clone WITHOUT the guard -> 6 failures, `** TEST FAILED **`. This completes the mutation test the agent was blocked from finishing: red demonstrably propagates through xcodebuild, so the harness is not green-by-construction.
- .gitkeep fix works: fresh clone has only .gitkeep in __Snapshots__, ZERO "Invalid Exclude" warnings, ZERO warnings total on `swift build --build-tests`.

COVERAGE: 204 of 210 execute on CI (97.1%). The 6 skipped are the only tests running nowhere. The 30 iOS skips (keychain entitlement, compile-time #if) all run on the macOS job, so union coverage is 204/210. Documented real reduction: macOS-only SwiftUI rendering now has zero CI coverage and rests on a manual pre-release step.

OPEN RISKS, NOT LOCALLY VERIFIABLE (carry into the release hand-off):
1. `OS=18.6` was NEVER executed — no iOS 18 runtime on this machine (only 26.2/26.5/27.0); the agent substituted iOS 26.2 locally. If macos-15 lacks that exact runtime the iOS job fails loudly on an unresolvable destination (deliberate, but it means iOS could be red on first run).
2. Xcode 26.3 never exercised (local is 26.6); its availability on macos-15 rests on the runner-images README.
3. Whether the package builds on older Xcode is now UNKNOWN in a new way: the Swift 6.0 error lived in code P2 deleted, so v2.0.0 may well compile on Xcode 16.x — untested either way. Do not claim a floor.

