---
title: PR 16 Complete — Theming Polish
type: note
permalink: gittickets/progress/pr-16-complete-theming-polish
tags: [progress, pr-16, theme, swiftui, snapshot-tests]
source_paths: [Sources/GitTickets/UI/SwiftUI/HeaderImage.swift, Tests/GitTicketsTests/UI/SwiftUI/SnapshotTests.swift]
source_paths_inferred: true
source_sha: ed614c17366c18af31b5728d8d6a64d03b3745b7
created: 2026-06-06
updated: 2026-07-12
reviewed: 2026-06-24
reviewed_by: human
---

PR 16 closes the theme-values audit loop the Pass 2 review flagged: every public field of `GitTicketsTheme` is now actually consumed by `GitTicketsView`, and we have a comprehensive snapshot-test safety net for the form layout going forward.

## Observations

- [verified] Snapshot baselines expanded to 13 tests covering form and key components. iOS Sim build clean. #verification
- [shipped] `HeaderImage` (`Sources/GitTickets/UI/SwiftUI/HeaderImage.swift`) — internal view that switches on `GitTicketsImageSource`. `.systemSymbol` → `Image(systemName:)`; `.named` → `Image(_:bundle:)` with `Bundle(identifier:)` lookup and main-bundle fallback; `.data` → `NSImage(data:)`/`UIImage(data:)` shim with system-symbol fallback when bytes don't decode. Mirrors the same pattern `ScreenshotThumbnail` uses for raw-bytes decoding. Availability constraint removed (`@available` attribute deleted). #pr-16
- [shipped] `GitTicketsView.headerIcon` wraps `HeaderImage` when `theme.headerImage != nil`; otherwise the default `exclamationmark.bubble` symbol — preserving the current look for adopters who don't override. The icon's `font(.title2)` + `.foregroundStyle(.tint)` modifiers carry through so a custom symbol picks up the host's accent color automatically. #pr-16
- [shipped] `GitTicketsView.submitButton(configuration:)` extracted as `@ViewBuilder` with a switch on `theme.submitButtonStyle`. Each enum case (`.bordered`, `.borderedProminent`, `.plain`) returns a Button with its own concrete `buttonStyle(_:)` type — the SwiftUI button styles aren't unifiable into a single expression, so the switch is the only path. #pr-16
- [shipped] Snapshot tests (`Tests/GitTicketsTests/UI/SwiftUI/SnapshotTests.swift`, `#if os(macOS)`). 13 test methods across multiple components. Uses the existing `swift-snapshot-testing` dep — no new dependencies. #pr-16
- [snapshot-test-pattern] SwiftUI views snapshot via `NSHostingController` wrapping with an explicit frame and `appearance` override. Two gotchas locked in for the next person: (1) without `controller.view.frame = NSRect(origin: .zero, size: ...)` the strategy crashes with "View not renderable to image at size (0.0, 0.0)"; (2) `.preferredColorScheme(.dark)` on the SwiftUI view does NOT propagate to `NSHostingController`'s `NSAppearance` in the test-runner context — set `controller.view.appearance = NSAppearance(named: .darkAqua)` instead. Confirmed dark/light SHAs are distinct (different rendered output, not silently identical). #testing #snapshot-tests
- [snapshot-strategy] Baseline coverage: PrivacyBanner (4 tests: light/dark/private-repo/override-copy), GitTicketsView form (2 tests: light/dark), IssueStateCard (4 tests: no-replies and error states × public/private repo), IssueHeader (2 tests: public/private repo), ReportCard with diagnostics (1 test). Targets stable, deterministic surfaces driven entirely by inputs or fixed copy, with no policy/validation state churn. #scope
- [ci-skip] `setUpWithError()` skips snapshot tests on CI (checks `CI` environment variable; `TEST_RUNNER_CI=true` from xcodebuild gets translated to `CI=true`). Baselines are deliberately untracked because rendered bytes depend on exact OS/font rasterizer, so CI would record-and-fail every run without saying anything about the code. Tests run locally before release. #testing
- [audit-closed] [[Audit Pass 2 — Post-Submit-Wiring Sweep]]'s "theme fields populated but never read internally" deferred item is now closed — every public field of `GitTicketsTheme` (accentColor, titleFont, bodyFont, monospacedFont, cornerRadius, headerImage, submitButtonStyle) is read at least once by `GitTicketsView` or one of its subviews. The audit-shape sweep on the next review pass should confirm no new declared-but-unread surfaces. #audit
- [defer] Snapshot tests are macOS-only — iOS Sim snapshot testing would couple us to a specific Simulator runtime version and the unit-test bundle has no host app for layout sizing. macOS gives us a single rendering substrate that catches visual regressions in the theme code path. iOS-specific layout differences would surface in Memophant's sibling iOS work, not the package's own tests. #scope

## Relations

- closes [[Audit Pass 2 — Post-Submit-Wiring Sweep]] theme-values-unread deferred item
- follows [[PR 14 Complete — UIKit Container]]
- precedes PR 17 documentation + PR 19 examples polish
