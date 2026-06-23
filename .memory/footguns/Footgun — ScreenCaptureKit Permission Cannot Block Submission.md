---
title: Footgun — ScreenCaptureKit Permission Cannot Block Submission
type: note
permalink: gittickets/footguns/footgun-screen-capture-kit-permission-cannot-block-submission
tags:
- footgun
- macos
- permissions
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

On macOS, ScreenCaptureKit and `CGWindowListCreateImage` both require Screen Recording permission (System Settings → Privacy & Security). First-time call triggers a permission prompt; if denied, all subsequent calls return empty/black images silently.

## Observations

- [requirement] NEVER block submission on missing screen recording permission. Capture eagerly on user tap; on permission failure show "Screen Recording permission required — open System Settings…" with a Go button (using `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)`), and let the user submit without a screenshot. #ux #requirement
- [pattern] `ScreenshotCapture+macOS.swift` returns `Result<Data, ScreenshotError>` where `.permissionDenied` is a recoverable failure that the form surfaces inline, not as an error sheet. #pattern

## Relations

