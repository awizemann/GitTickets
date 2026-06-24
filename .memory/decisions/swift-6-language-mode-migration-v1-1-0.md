---
title: Swift 6 Language Mode Migration (v1.1.0)
type: note
permalink: gittickets/decisions/swift-6-language-mode-migration-v1-1-0
tags:
- swift6
- concurrency
- migration
- release
- v1.1.0
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

GitTickets migrated to the Swift 6 language mode, shipping as **v1.1.0** (release-prepped 2026-06-23; tag/push held pending validation in Memophant). Driven by the host app **Memophant** moving to Swift 6. **ZERO runtime-behavior change** — concurrency annotations + one deprecated-API rename + build config only.

## Observations
- [decision] `Package.swift`: swift-tools-version 5.9 → 6.0 + package-level `swiftLanguageModes: [.v6]` (library AND tests compile in Swift 6 mode; `-swift-version 6` confirmed passed to swiftc). Minimum toolchain now Swift 6.0 / Xcode 16+; runtime floor unchanged (macOS 13 / iOS 16). #swift6 #build
- [fix] ISO8601 statics (`RelaySubmitter.iso8601` / `iso8601NoFractional`) → `nonisolated(unsafe)`. Immutable-after-init, parse-only (inbound relay dates); outbound wire serialization (`RelayJSON.encoder`) untouched. Kept `ISO8601DateFormatter` (NOT `Date.ISO8601FormatStyle`) to preserve byte-identical parsing. NOT `@MainActor` — the relay submitter must stay off-main + Sendable. #concurrency
- [fix] `GitTicketsMenuItemFactory` enum + `MenuActionTarget` trampoline → `@MainActor`. Genuine AppKit UI construction; enforces the main-thread requirement that already held at runtime. Source-compatible for documented usage. (This was the "main-actor-isolated default value in a nonisolated context" error.) #appkit
- [fix] `DeviceInfo`: `String(validatingUTF8:)` → `String(validatingCString:)`. Pre-existing deprecation surfaced by the clean rebuild; pure rename, identical semantics. #cleanup
- [fix] 6 UI test classes → `@MainActor` (MenuItemFactory, ReportWindowController, Commands, MyIssuesCommands, View, Snapshot Tests). XCTest methods build `@MainActor` SwiftUI/AppKit types; they already ran on main. #testing
- [finding] The `AttributeScopes.SwiftUIAttributes` non-Sendable keypath warnings (`DiagnosticsRendering.highlighted`) emitted under Swift-5 `-strict-concurrency=complete` DO NOT fire in true v6 mode on Xcode 26.5 — a strict-mode-only artifact. `DiagnosticsRendering` left untouched. Empirical-first beat speculative fixing. #gotcha
- [gotcha] A `swift build -Xswiftc -strict-concurrency=complete` catalog run off a stale `.build` is partially INCREMENTAL and UNDER-reports (it missed the DeviceInfo deprecation). Always clean-build (`rm -rf .build`) for an authoritative warning census. #gotcha #build
- [verification] macOS: clean `swift build` + `swift build --build-tests` → 0 warnings / 0 errors in v6. iOS: SwiftPM cross-compile of the library to `iphonesimulator26.5` (`-target arm64-apple-ios16.0-simulator`) → 0/0, compiles all `#if os(iOS)` source. `swift test` → 210/210. #verification
- [gotcha] Snapshot baselines (`Tests/…/__Snapshots__/`) are GITIGNORED (`.gitignore`: `__Snapshots__/`) — local-only by design (the SnapshotTests doc says "first run records the baseline images"). `test_formLight` / `test_formDark` drift across macOS versions (they fail identically on pristine main — env, not our change). Re-record locally with `SNAPSHOT_TESTING_RECORD=all swift test --filter test_form` (`record=failed` did NOT honor in snapshot-testing 1.19.2). Decision: keep gitignored, do NOT commit baselines (CI / other-OS fragility). #testing #footgun
- [gotcha] `xcodebuild -scheme GitTickets` for an iOS destination fails "Supported platforms … is empty" under beta Xcode 26.5 (bare-SPM-package scheme bug). Does NOT affect `swift build`/`swift test` or dependency consumption. Verify iOS via SwiftPM cross-compile instead. #footgun #ios
- [cross-repo] Memophant's own audit (branch `audit/swift6-language-mode`, 2026-06-23) INDEPENDENTLY measured GitTickets' exact 3 Swift-6 errors (RelaySubmitter ISO8601 ×2 + GitTicketsMenuItemFactory main-actor default) and flagged "GitTickets Swift-6-readiness = separate optional follow-up." v1.1.0 IS that follow-up. Memophant flips its app target PER-TARGET (deps keep their own mode), so v1.1.0 de-risks a GLOBAL flip rather than unblocking the per-target one. #memophant #dependencies
- [release] v1.1.0 release-prep committed LOCAL only (a52e505 — `UserAgent.sdkVersion` 1.1.0, CHANGELOG `[1.1.0]`, README Status; also corrected stale CHANGELOG links github.com/alanw → awizemann). Tag + push to github.com/awizemann/GitTickets HELD pending Alan's go + Memophant validation. Tracking task `t-822c22e2`. #release

## Relations
- relates_to [[Architecture — Client SDK + Optional Relay]]
- relates_to [[Footgun — Sendable Lies in Public Types]]
- relates_to [[Memophant Integration Complete — Help → Report an Issue]]
- follows [[Phase 1 Complete — PR 17 / 18 / 19 / 20 Polish + Release]]
