---
title: PR 6 Complete — Screenshot Capture
type: note
permalink: gittickets/progress/pr-6-complete-screenshot-capture
tags:
- progress
- pr-6
- screenshot
- macos
- ios
---

PR 6 (Screenshot) shipped 2026-06-04. Platform-specific capture is live; form-level wiring lands in PR 12.

## Observations

- [verified] 78/78 tests green on macOS. iOS Sim build clean. #verification
- [files-shipped] `Sources/GitTickets/Screenshot/` — `ScreenshotCapture.swift`, `ScreenshotCapture+macOS.swift`, `ScreenshotCapture+iOS.swift`. Plus error-equality tests. #files
- [decision] macOS uses ScreenCaptureKit's `SCScreenshotManager.captureImage` on macOS 14+; falls back to a one-shot `SCStream` adapter for macOS 13. Skip `CGWindowListCreateImage` — SCK covers our floor and CGWindow is deprecated in macOS 14+. #macos
- [decision] iOS uses `UIGraphicsImageRenderer` over `UIWindow.drawHierarchy(in:, afterScreenUpdates: false)`. No permission prompt — entirely in-process. #ios
- [decision] Capture returns `Result<Data, ScreenshotCaptureError>` — never throws. Errors are recoverable so the form surfaces them inline and lets the user submit text-only. NEVER block submission on screenshot failure. Cross-references [[Footgun — ScreenCaptureKit Permission Cannot Block Submission]]. #invariant
- [decision] macOS permission detection is by **string-matching** the SCK error text for "permission" / "not granted" / "tccd". Fragile — Apple could change the message — but there's no public `errSCStreamPermissionDenied` constant. Document as a known fragility. #footgun
- [decision] iOS key window resolved via `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)`. Returns `.noActiveWindow` if nothing matches — possible during early app launch. #ios
- [decision] `@preconcurrency import ScreenCaptureKit` to silence Swift 6 sendability warnings on the SCK types under tools-version 5.9. Revisit when migrating to Swift 6. #tech-debt
- [decision] PNG encoding on macOS via `NSBitmapImageRep(cgImage:).representation(using: .png)`; on iOS via `UIImage.pngData()`. Standard one-liners. #encoding
- [decision] NEVER auto-capture in the background. Capture is initiated only on direct user action (tapping "Add Screenshot" in PR 12 form). Documented in code comments. #ux #privacy
- [scope] No annotation / mask tool in PR 6 — comes alongside the form in PR 12. Out of scope here. #scope
- [scope] No automated capture tests — would need a real display + windowed app context. Verification deferred to the sample apps in PR 19. #testing

## Relations

- precedes PR-7-Networking-Core
- realizes [[Architecture — Client SDK + Optional Relay]]
- depends_on [[Footgun — ScreenCaptureKit Permission Cannot Block Submission]]
- follows [[PR 5 Complete — Diagnostics]]
