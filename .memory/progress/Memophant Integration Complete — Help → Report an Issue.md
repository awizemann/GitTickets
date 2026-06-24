---
title: Memophant Integration Complete — Help → Report an Issue
type: note
permalink: gittickets/progress/memophant-integration-complete-help-report-an-issue
tags:
- progress
- integration
- memophant
- real-world-test
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

Memophant (a shipping macOS SwiftUI/SwiftData app) is now wired against the GitTickets SDK as a local SwiftPM dependency at `../GitTickets`. Single Memophant build passes; menu item disabled until placeholders replaced. This is the first real-world host of the SDK and exercises the programmatic `submit(_:)` path PR 8 was designed for.

## Observations

- [verified] `xcodebuild -scheme Memophant -destination platform=macOS` BUILD SUCCEEDED with GitTickets linked. #verification
- [verified] GitTickets `swift test` 130/130 still green after the public surface bump. #verification
- [files-shipped] In Memophant: `Memophant.xcodeproj/project.pbxproj` (XCLocalSwiftPackageReference + product dep + framework link), `Memophant/App/MemophantApp.swift` (init, Commands, Window scene), `Memophant/Features/GitTickets/{GitTicketsConfig, GitTicketsReportView, GitTicketsCommands}.swift`. In GitTickets: promoted `DiagnosticsCollector`, `DiagnosticsBlob`, `ScreenshotCapture`, `ScreenshotCaptureError` to public. #files
- [decision] Public surface bump (DiagnosticsCollector + DiagnosticsBlob + ScreenshotCapture + ScreenshotCaptureError) — needed by hosts that present their own UI on top of `submit(_:)`. Previously internal under the assumption PR 12's GitTicketsView would be the only consumer. This integration is exactly the programmatic use case PR 8 was designed for. #api #scope-bump
- [decision] Integration ships its own minimal SwiftUI form (`GitTicketsReportView`) rather than waiting for PR 12. ~200 LOC. Uses every public API the package surfaces: configure / submit / DiagnosticsCollector / ScreenshotCapture / DiagnosticsBlob / SubmittedIssue / Report. The exhaustive use surfaced the missing public types in seconds. #scope
- [pattern] `GitTicketsConfig.isProperlyConfigured` flag drives BOTH the menu item's `.disabled` state AND `configureIfPossible()`'s no-op. Same source of truth — no way to ship a build where the menu item enables but configure didn't run. #defensive
- [pattern] Standalone `Window` scene (not `WindowGroup`) for the report sheet so re-invoking the menu brings the existing window forward instead of spawning duplicates. SwiftUI default behavior. #pattern
- [pattern] `OSLogGitTicketsLogger` bridges `GitTicketsLogger` → `os.Logger(subsystem: Bundle.main.bundleIdentifier, category: "GitTickets")`. SDK lines show up in Console.app under the same subsystem as the rest of Memophant. #observability
- [decision] Local SPM path is `../GitTickets` (relative). Both repos live as siblings in the user's `Development/` folder — common convention. Switching to a published Git URL is one edit when the package goes public. #integration
- [verification-deferred] Real round-trip verification: user pastes their deployed Vercel relay URL + hex secret + repo coords into `GitTicketsConfig.swift`, builds Memophant, hits Help → Report an Issue, submits. Expected: 200 response, GitHub issue created in their repo within ~2s, "Filed as issue #N" + Open on GitHub button in the success panel. #verification

## Relations

- precedes PR-11-Device-Flow-Submitter
- realizes [[Architecture — Client SDK + Optional Relay]]
- exercises [[PR 8 Complete — Relay Submitter]]
- exercises [[PR 9 Complete — Vercel Relay]]



## Update — dependency is REMOTE now (2026-06-23, v1.1.0 cycle)
The "local SwiftPM path `../GitTickets`" framing above is HISTORICAL. Memophant now consumes GitTickets as a REMOTE Swift package — `XCRemoteSwiftPackageReference` → github.com/awizemann/GitTickets, requirement `upToNextMajorVersion` from 1.0.0 (currently pinned v1.0.0 @ rev 014b8d4). The predicted "switch to a published Git URL when the package goes public" happened. The local-path override now returns only as a temporary test harness when validating an unreleased GitTickets (e.g. v1.1.0) before tagging. See [[Swift 6 Language Mode Migration (v1.1.0)]].
