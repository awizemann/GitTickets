---
title: PR 16 Complete — Theming Polish
type: note
permalink: gittickets/progress/pr-16-complete-theming-polish
tags:
- progress
- pr-16
- theme
- swiftui
- snapshot-tests
---

PR 16 closes the theme-values audit loop the Pass 2 review flagged: every public field of `GitTicketsTheme` is now actually consumed by `GitTicketsView`, and we have a small snapshot-test safety net for the form layout going forward.

## Observations

- [verified] 203/203 Swift green (was 197 — +6 snapshot tests). iOS Sim build clean. 37/37 Vercel + 32/32 Cloudflare untouched. #verification
- [shipped] `HeaderImage` (`Sources/GitTickets/UI/SwiftUI/HeaderImage.swift`) — internal view that switches on `GitTicketsImageSource`. `.systemSymbol` → `Image(systemName:)`; `.named` → `Image(_:bundle:)` with `Bundle(identifier:)` lookup and main-bundle fallback; `.data` → `NSImage(data:)`/`UIImage(data:)` shim with system-symbol fallback when bytes don't decode. Mirrors the same pattern `ScreenshotThumbnail` uses for raw-bytes decoding. #pr-16
- [shipped] `GitTicketsView.headerIcon` wraps `HeaderImage` when `theme.headerImage != nil`; otherwise the default `exclamationmark.bubble` symbol — preserving the current look for adopters who don't override. The icon's `font(.title2)` + `.foregroundStyle(.tint)` modifiers carry through so a custom symbol picks up the host's accent color automatically. #pr-16
- [shipped] `GitTicketsView.submitButton(configuration:)` extracted as `@ViewBuilder` with a switch on `theme.submitButtonStyle`. Each enum case (`.bordered`, `.borderedProminent`, `.plain`) returns a Button with its own concrete `buttonStyle(_:)` type — the SwiftUI button styles aren't unifiable into a single expression, so the switch is the only path. #pr-16
- [shipped] Snapshot tests (`Tests/GitTicketsTests/UI/SwiftUI/SnapshotTests.swift`, `#if os(macOS)`). Six baselines under `__Snapshots__/SnapshotTests/`: PrivacyBanner light/dark/private/override + GitTicketsView unconfigured light/dark. Uses the existing `swift-snapshot-testing` dep — no new dependencies. #pr-16
- [snapshot-test-pattern] SwiftUI views snapshot via `NSHostingController` wrapping with an explicit frame and `appearance` override. Two gotchas locked in for the next person: (1) without `controller.view.frame = NSRect(origin: .zero, size: ...)` the strategy crashes with "View not renderable to image at size (0.0, 0.0)"; (2) `.preferredColorScheme(.dark)` on the SwiftUI view does NOT propagate to `NSHostingController`'s `NSAppearance` in the test-runner context — set `controller.view.appearance = NSAppearance(named: .darkAqua)` instead. Confirmed dark/light SHAs are distinct (different rendered output, not silently identical). #testing #snapshot-tests
- [snapshot-strategy] Targeted only stable, deterministic surfaces: `PrivacyBanner` (driven entirely by inputs) and the unconfigured GitTicketsView placeholder (no policy state, fixed copy). Didn't snapshot the active form — its layout changes with validation state, attachment presence, device-flow state, and theme. Avoiding churn there is more valuable than coverage. PR 19 (Examples polish) is the natural place to add full-form snapshots once the sample-app validation freezes the layout. #scope
- [audit-closed] [[Audit Pass 2 — Post-Submit-Wiring Sweep]]'s "theme fields populated but never read internally" deferred item is now closed — every public field of `GitTicketsTheme` (accentColor, titleFont, bodyFont, monospacedFont, cornerRadius, headerImage, submitButtonStyle) is read at least once by `GitTicketsView` or one of its subviews. The audit-shape sweep on the next review pass should confirm no new declared-but-unread surfaces. #audit
- [defer] Snapshot tests are macOS-only — iOS Sim snapshot testing would couple us to a specific Simulator runtime version and the unit-test bundle has no host app for layout sizing. macOS gives us a single rendering substrate that catches visual regressions in the theme code path. iOS-specific layout differences would surface in Memophant's sibling iOS work, not the package's own tests. #scope

## Relations

- closes [[Audit Pass 2 — Post-Submit-Wiring Sweep]] theme-values-unread deferred item
- follows [[PR 14 Complete — UIKit Container]]
- precedes PR 17 documentation + PR 19 examples polish
