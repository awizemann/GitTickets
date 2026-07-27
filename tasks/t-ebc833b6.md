---
id: t-ebc833b6
title: v2.0.0 P2: collapse ScreenCaptureKit to SCScreenshotManager
status: done
added: 2026-07-25
priority: high
---

## Description

Phase 2 of v2.0.0. Replace the hand-rolled SCStream one-shot capture with SCScreenshotManager.captureImage (macOS 14+), deleting the OneShotStream class and the continuation double-resume guard. This also removes the Swift 6.0 compile error at ScreenshotCapture+macOS.swift:88 that is currently the sole cause of the repo's red CI. Owns Sources/GitTickets/Screenshot/** only. Isolated worktree, parallel with P1 and P3.

## Plan

Base: branch release/v2.0.0 at ab63920 (floor already macOS 14 / iOS 18, so SCScreenshotManager is available unconditionally).

FILE OWNERSHIP (strict):
- OWNS: Sources/GitTickets/Screenshot/** and any Tests/ file exercising screenshot capture.
- MUST NOT TOUCH: anything else. P1 owns the rest of Sources/, P3 owns CI + SnapshotTests + .gitignore, P4 owns docs/version.

WHY THIS IS THE FIX: Sources/GitTickets/Screenshot/ScreenshotCapture+macOS.swift:88 has a `Task { }` inside withCheckedThrowingContinuation that Xcode 16.2 / Swift 6.0 rejects ("task-isolated value of type '() async -> ()' passed as a strongly transferred parameter"). Xcode 26.6 / Swift 6.3.3 accepts it, which is why local builds are green and CI is red. Do NOT patch the Task — delete the code that needs it.

WORK:
1. Replace the OneShotStream/SCStream capture path with SCScreenshotManager.captureImage(contentFilter:configuration:) — verified API_AVAILABLE(macos(14.0)), returns CGImage directly, async.
2. Delete OneShotStream entirely: the SCStreamOutput delegate, the NSLock, the didResume flag, the finish(returning:)/finish(throwing:alreadyAdded:) pair, and the @unchecked Sendable conformance. All of it existed only to make a streaming API behave like a one-shot call.
3. Preserve exactly: how SCContentFilter and SCStreamConfiguration are built, the resulting CGImage, and the error surface callers see (same GitTicketsError cases, same throwing behavior for permission-denied and no-display cases).
4. Keep the macOS 13 crash-safety comments only if still true; delete them if the risk they describe is gone with the class.

VERIFY:
- swift build → 0 warnings, 0 errors
- swift test → all 210 pass
- Confirm by reading the compiler output that the file compiles with no concurrency diagnostics.
- HONEST LIMIT: actual screen capture cannot be exercised headlessly (needs Screen Recording TCC permission and a real display). Do NOT claim runtime verification you did not do. Instead, prove equivalence by careful reading and state plainly which paths are compile-verified only. Alan will exercise capture in a real app after tagging.

Then a fresh-eyes adversarial self-audit: re-read cold, specifically checking that no error path silently changed from throwing to returning (or vice versa), that permission-denied still surfaces the same error, and that nothing now resumes a continuation zero times (a hang) — the failure mode the deleted guard protected against. Report honestly.

Commit in the worktree and report branch + SHA + diffstat + the exact line count deleted.

## Artifacts

DONE 2026-07-25. Commit 0e8a5b1 on worktree-agent-ae0e92726fc7f308f (parent ab63920). 2 files changed, 8 insertions, 98 deletions — net -90 lines.

KEY FINDING (verified independently by the orchestrator, not just claimed): this was DEAD-CODE DELETION, not a behavioral rewrite. At base, ScreenshotCapture+macOS.swift:27 already read `if #available(macOS 14.0, *)` and called SCScreenshotManager.captureImage with the exact same filter and configuration; OneShotStream/SCStream was only the `else` fallback for macOS 13. So at a macOS 14 floor that whole branch was statically unreachable, and every Sonoma-or-later user was ALREADY on the SCScreenshotManager path in production.

Corollary worth remembering: the Swift 6.0 concurrency error that has kept CI red since the Swift 6 migration lived in code that no macOS 14+ user ever executed. The fix was deleting a fallback, not repairing a live path.

Verified by orchestrator: the SCScreenshotManager path and the full error surface (.captureFailed("No displays available"), .encodingFailed, .permissionRequired, .captureFailed(describing:)) are byte-identical to base; platformCapture returns Result (not throwing), so no throw/return flip was possible. Orphan check for all deleted symbols (OneShotStream, didResume, SCStreamOutput, finish(returning:), alreadyAdded) across Sources/ and Tests/ at the commit: zero hits.

Agent-reported verification: swift build 0 warnings/0 errors from clean; swift test 210/210; xcodebuild generic iOS Simulator BUILD SUCCEEDED. Combined-tree verification is still pending (P5) — a per-phase green does not imply a merged green.

AGENT JUDGMENT CALLS (both accepted):
1. Kept `@preconcurrency import ScreenCaptureKit`. Provably unnecessary under Swift 6.3.3 but it suppresses Sendable diagnostics for non-Sendable SCContentFilter/SCStreamConfiguration crossing an await, and CI was Swift 6.0 at the time. Once P3's runner bump lands and CI is confirmed green on a newer Xcode, this becomes a candidate for removal — cosmetic, low priority, do not churn for it.
2. Fixed a stale comment in ScreenshotCapture.swift (its own file) that described a CGWindowListCreateImage fallback which never existed. 2 lines.

USEFUL SIDE FINDING: on a fresh checkout the first `swift test` reports 6 failures — the 6 snapshot tests recording reference PNGs into the gitignored __Snapshots__/ on first run. Every later run is 210/210. This independently corroborates the P3 snapshot analysis: on CI they record fresh and pass vacuously.

RUNTIME GAP (must be honored in the release hand-off): real screen capture is compile-verified ONLY — no TCC permission or display available headlessly. Untested at runtime: the success path (captureImage -> CGImage -> PNG), permission-denied, and no-display. Alan exercises these in his own app after tagging.

