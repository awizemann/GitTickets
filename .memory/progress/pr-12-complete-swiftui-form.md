---
title: PR 12 Complete — SwiftUI Form
type: note
permalink: gittickets/progress/pr-12-complete-swiftui-form
tags:
- progress
- pr-12
- swiftui
- ui
- device-flow
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

PR 12 ships the package's own SwiftUI form. The integration pattern in Memophant (host owns the inline form, calls `GitTickets.submit(_:)` programmatically) is now superseded by `GitTicketsView()` — Memophant can switch in PR 13's window-controller wiring or via a single sheet presentation.

## Observations

- [verified] 182/182 Swift tests green (was 165 — +17 new). 37/37 Vercel + 32/32 Cloudflare untouched and re-confirmed green. iOS Sim build clean. #verification
- [shipped] `Sources/GitTickets/UI/SwiftUI/` — six files. `PrivacyBanner` (public), `DiagnosticsDisclosure` (public), `ReportFormFields` (internal), `ScreenshotThumbnail` (internal), `DeviceFlowSheet` (public), `GitTicketsView` (public). Cross-platform: `macOS 13+ / iOS 16+`. `#if canImport(AppKit)` / `canImport(UIKit)` only for `NSImage`/`UIImage` + `ASPresentationAnchor` lookup; everything else is pure SwiftUI. #pr-12
- [shipped] `GitTicketsView` is the public entry point. Reads `Configuration` from `GitTickets.configuration` singleton with a test-only injection init that lets previews + tests stub the config / submit closure / dismiss / diagnostics provider. State machine: `idle / submitting / succeeded / failed`. The intercept on `GitTicketsError.deviceFlowNotAuthorized` flips `showingDeviceFlowSheet = true` rather than surfacing it as a failure — the form drives the OAuth UX so the host doesn't have to plumb it through. After the sheet completes success, `submit()` re-fires automatically. #pr-12
- [shipped] `DeviceFlowSheet` is the load-bearing piece. Calls `DeviceFlowCoordinator.requestAuthorization()` on appear, shows the user code in monospaced bold, opens `ASWebAuthenticationSession(url: verificationURIComplete, callbackURLScheme: nil)` with `prefersEphemeralWebBrowserSession = true`, and polls in parallel. When the token arrives we cancel the auth session, write to `TokenStore`, and call `onComplete(.success)`. Matches the [[Footgun — iOS Device Flow Return-to-App UX]] recipe exactly: sheet stays open in-app, polling is the return mechanism, no Universal Links needed. `WebAuthSessionBox` retains the session so it survives past `start()` returning — without that the browser dismisses immediately. `PresentationContextProvider` does the cross-platform window lookup (NSApp.keyWindow on macOS, `UIWindowScene` foreground-active scan on iOS). #device-flow
- [decision] Attachment UI is hidden entirely when `auth == .deviceFlow` (`GitTicketsView.supportsAttachments(auth:)` gate). Matches the existing [[Footgun — No Public GitHub Attachment API]] rule and the Submitter's pre-flight rejection. The button never appears, so users don't get the confusing "I attached an image" + "but it didn't go" experience. #ux
- [decision] File-picker over screenshot capture — same call Memophant made and for the same reason. `ScreenshotCapture.capture()` on macOS triggers a Screen Recording permission prompt the first time, which is an aggressive ask just to attach an image to a bug report. The form uses SwiftUI's `fileImporter` (cross-platform, works in sandboxed apps) and explains the system screenshot shortcut in the tip text. `ScreenshotCapture` from PR 6 remains available for adopters who want to wire their own button. #decision
- [decision] Snapshot tests deferred to PR 16. The task scope said "Snapshot tests" but locking layout snapshots now would just churn during the Memophant integration validation pass — every padding tweak forces a re-record. PR 16 (theming polish) is the natural place: layout stable, theming knobs documented, snapshots make sense. The dep (`swift-snapshot-testing`) stays in the package. #scope
- [partial-wiring] Theme values consumed by PR 12: `accentColor` (outer `.tint()`), `titleFont` (header), `bodyFont` (title field + body editor), `monospacedFont` (diagnostics blob), `cornerRadius` (banner background + disclosure background + body editor border). Theme values still unread: `headerImage`, `submitButtonStyle`. Audit Pass 2 flagged these for "PR 12+"; the bigger two (the image source enum needs three-case rendering; the button-style enum requires a switch-on-style ViewBuilder) properly belong to PR 16. Flagged so the next audit catches it. #scope
- [shape-match-avoided] `GitTicketsView` dispatches the `submit` closure that defaults to `GitTickets.submit(_:)` — but the public `init()` uses the singleton via the same injection point the tests use. No surface declared-but-not-dispatched: the sheet shows the form, the form calls submit, submit intercepts the device-flow gap and presents `DeviceFlowSheet`, the sheet writes the token and re-fires submit. Audit shape covered end-to-end in `test_dependencyInjectedInitBuildsBothBranches` (build path) + the existing PR 11 `test_deviceFlowDispatchReachesSubmitter` (dispatch path). #pattern
- [test-pattern] All new tests are pure-state. `PrivacyBanner.copy(repo:policy:)` is a static helper so the test asserts wording without rendering. `GitTicketsView.submitDisabledReason(state:title:bodyText:hasAcknowledgedPrivacy:requireExplicitConsent:)` and `supportsAttachments(auth:)` and `mimeType(for:)` are likewise static. `ScreenshotThumbnail.makeImage(from:)` is exposed so tests can verify the decode round-trip with a 1x1 PNG fixture (base64 in the test, no binary in the repo). The view-tree only gets touched in one test that confirms `body` builds for both configured and unconfigured paths. #testing
- [defer] Memophant migration to `GitTicketsView()`: not part of this PR. Memophant's existing inline view (`Memophant/Features/GitTickets/GitTicketsReportView.swift`) keeps working — it's the example the audit memory note documents as the v1 integration shape. The natural Memophant switch is two lines (drop the inline view, present `GitTicketsView()` in the sheet) and lands when PR 13 ships the AppKit factory. #next
- [defer] `GitTicketsCommands` (SwiftUI commands group) + `GitTicketsMenuItemFactory.makeReportIssueItem()` + `ReportWindowController` are PR 13's scope — separate PR per the task board. The form they wrap is ready. #next

## Relations

- follows [[PR 11 Complete — Device Flow Submitter]]
- consumes [[Footgun — iOS Device Flow Return-to-App UX]]
- consumes [[Footgun — No Public GitHub Attachment API]]
- partially_addresses [[Audit Pass 2 — Post-Submit-Wiring Sweep]] theme-values-unread deferred item
- enables PR 13 SwiftUI Commands + AppKit factory
- supersedes Memophant inline `GitTicketsReportView.swift` (next Memophant session can switch)
