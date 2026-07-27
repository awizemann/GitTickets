---
id: t-bd61de6c
title: v2.0.0 P1: availability cleanup + SwiftUI modernization
status: done
added: 2026-07-25
priority: high
---

## Description

Phase 1 of the v2.0.0 platform-floor release. Delete the @available annotations made redundant by the macOS 14 / iOS 18 floor, and adopt the newer SwiftUI APIs that genuinely reduce code at that floor. Owns Sources/GitTickets/** EXCEPT Screenshot/, plus Tests/ availability annotations EXCEPT SnapshotTests.swift. Runs in an isolated git worktree, parallel with P2 and P3.

## Plan

Base: branch release/v2.0.0 at ab63920 (floor already raised to macOS 14 / iOS 18).

FILE OWNERSHIP (strict — other agents own the rest):
- OWNS: Sources/GitTickets/** except Sources/GitTickets/Screenshot/**
- OWNS: Tests/GitTicketsTests/** except UI/SwiftUI/SnapshotTests.swift
- MUST NOT TOUCH: Sources/GitTickets/Screenshot/ (P2), .github/workflows/ (P3), SnapshotTests.swift (P3), .gitignore (P3), CHANGELOG.md / README.md / docs/ / UserAgent.swift sdkVersion (P4), Package.swift platform lines.

WORK:
1. Delete every @available annotation whose requirement is at or below macOS 14 / iOS 18 — these are now no-ops. ~35 sites, mostly @available(macOS 13.0, iOS 16.0, *) across UI/SwiftUI, plus @available(macOS 13.0, *) in UI/AppKit and @available(iOS 16.0, *) in UI/UIKit. Removal cascades: a type losing its annotation lets every referencing site drop theirs too.
2. KEEP any annotation above the floor (e.g. macOS 15+/iOS 19+) — verify each before deleting rather than pattern-matching.
3. Collapse `if #available` / #available branches now statically true, deleting the dead fallback arm.
4. SwiftUI modernization, conservative: adopt APIs available at the new floor only where they measurably shrink or clarify code (e.g. ContentUnavailableView for empty states, two-parameter onChange(of:initial:)). NO rearchitecture. There is no ObservableObject/@Observable in Sources/ — do not introduce an observation layer.

CONSTRAINT — no compiler is forcing any of this: the floor bump produced ZERO new deprecation warnings on macOS or iOS. So every modernization edit must be justified by real code reduction or clarity, never novelty. Zero behavior change. When a change is merely lateral, skip it and say so.

VERIFY (all required, real runs not assertions):
- swift build → 0 warnings, 0 errors
- swift test → all 210 pass
- xcodebuild -scheme GitTickets -destination 'generic/platform=iOS Simulator' -skipPackagePluginValidation build → BUILD SUCCEEDED (ignore the benign IDERunDestination "Supported platforms ... is empty" log)
- Confirm no public API changed: symbol removal or signature change is out of scope for this phase.

Then a fresh-eyes adversarial self-audit: re-read the diff cold, hunting for an annotation deleted that was actually load-bearing, a dead branch removed that had a side effect, and any behavior drift. Report findings honestly including anything left undone.

Commit in the worktree and report branch + SHA + a diffstat.

## Artifacts

DONE 2026-07-25. Commit 79d58ee on worktree-agent-a92053c78345842ae (parent ab63920). 26 files changed, 4 insertions, 66 deletions.

WHAT LANDED: 62 redundant @available annotations deleted (54 `macOS 13.0, iOS 16.0`, 6 `macOS 13.0`, 2 `iOS 16.0`) — well above the ~35 estimated in the plan. Plus 4 stale header comments refreshed to say macOS 14+ / iOS 18+. The 4 insertions ARE those comments.

VERIFIED BY ORCHESTRATOR (not just agent-claimed): the diff is purely annotation and comment removal — filtered every removed line that was not an @available or a comment and got an empty set, so ZERO executable lines changed. `@available(*, unavailable)` on GitTicketsViewController.init(coder:) is preserved at line 33.

Agent verification: swift build 0 warnings/0 errors from a clean .build; swift test 210/210; xcodebuild generic iOS Simulator BUILD SUCCEEDED targeting ios18.0-simulator. Public API stability was PROVEN rather than asserted — swift-api-digester dump before/after plus -diagnose-sdk, with the only delta being availability metadata (which only widens, and is moot since no adopter can sit below the declared floor). Every breaking-change category empty.

THE MODERNIZATION HALF OF THIS PHASE FOUND NOTHING, AND THAT IS THE HONEST ANSWER:
- ContentUnavailableView: skipped, correctly. The three candidate sites (GitTicketsMyIssuesView emptyState/failedState, IssueStateCard) are deliberately designed cards — tinted rounded icon tile, card surface, hairline border, maxWidth 420. Substituting the system view is a visual redesign, not a code reduction, and GitTicketsView is snapshot-covered. The agent called this "not lateral — actively regressive", which is the right call.
- onChange(of:initial:): inapplicable. There is not a single `onChange` call site anywhere in Sources/ or Tests/.
- #available collapsing: zero sites in P1's ownership; the repo's only one was ScreenshotCapture+macOS.swift:27, which P2 deleted.
So Alan's chosen "Tight + SwiftUI modernization" scope yielded no modernization work. The higher floor unlocked nothing this codebase wanted. Worth remembering before assuming a floor bump implies modernization wins.

DELIBERATELY LEFT ALONE: NSWindow.isVisibleOnAnyScreen's `for...where { return true }` could be `contains(where:)` — unrelated to the floor bump, left out to keep the diff purely mechanical. Reasonable; candidate for a future tidy pass, not this release.

NEW FINDING SURFACED BY THIS PHASE (routed to P3, which owns the files): on a fresh clone `swift build` warns `Invalid Exclude '.../__Snapshots__': File not found`, because Package.swift excludes a directory that is gitignored and therefore absent until the snapshot tests record baselines once. Permanent on CI (always a clean checkout) and it undermines any 0-warnings gate. Orchestrator established the blast radius: NOT consumer-visible — a throwaway consumer package built against a fresh clone via a path dependency compiles with zero warnings, because SPM only builds test targets for the root package. So: CI/local annoyance, not a published defect.

Also routed to P3: SnapshotTests.swift:17 still carries a no-op @available(macOS 13.0, *); P1 correctly left it because P3 owns that file.

WORKTREE BASE NOTE: this agent (and P2) reported its worktree initially checked out at 51b13d9 rather than ab63920 and fast-forwarded itself. Orchestrator confirmed all three worktree branches are descendants of ab63920, so no work was built against the stale floor.

