---
title: Footgun — Sendable Lies in Public Types
type: note
permalink: gittickets/footguns/footgun-sendable-lies-in-public-types
tags:
- footgun
- swift
- concurrency
- sendable
---

Three distinct Sendable / concurrency mistakes we shipped in PR 1–6 and fixed in code review:

1. **`nonisolated(unsafe) static var` for a non-trivial value type.** `Configuration` is a struct containing `URL`, `Data`-backed `SharedSecret`, and policy structs. Assignment is NOT atomic; a `configure(_:)` call concurrent with a `configuration` read can return a torn struct, surfacing as a crash on the next URL/Data access in release builds. TSan flags it immediately in debug.
2. **`Sendable` enum carrying a reference type.** `GitTicketsImageSource.named(String, bundle: Bundle)` declared `Sendable` while `Bundle` is a non-`Sendable` reference type. Compiler accepted it (no nominal check on enum cases in Swift 5.9) but it was a lie — the host could store a bundle and have it accessed concurrently from MainActor (UI) and a background task (submitter).
3. **`CheckedContinuation` resumed twice.** `OneShotStream` (ScreenCaptureKit fallback) resumed the continuation on every sample buffer it received. SCStream delivers frames continuously until `stopCapture()` completes asynchronously — second frame → fatal `SWIFT TASK CONTINUATION MISUSE` and host-app crash.

Discovered in code review of PR 1–6.

## Observations

- [rule] Use an `NSLock`-guarded box (or `OSAllocatedUnfairLock`, or an `actor`) for any static mutable state that holds a non-trivial value type. `GitTickets.configurationStorage` is the reference implementation. #swift #concurrency
- [rule] `nonisolated(unsafe)` suppresses the compiler's Sendable check but does NOT make multi-word value assignment atomic. The annotation is for "I promise to handle synchronization elsewhere" — if you didn't, you have a race. #swift
- [rule] When putting `: Sendable` on an enum, verify every associated-value type is `Sendable`. `Bundle`, `NSObject`-subclasses, and most reference types are not. If you need a bundle reference, store the bundle IDENTIFIER (a String) and resolve at point-of-use. #swift
- [rule] When wrapping a delegate-style API in a `CheckedContinuation`, guard the resume call with a lock + `didResume` flag. The delegate can fire multiple times; the continuation resumes exactly once. See `OneShotStream.finish(returning:)` for the pattern. #swift #screencapturekit
- [rule] When the delegate-style API also needs teardown (stopCapture, removeStreamOutput), do the teardown in the SAME guarded block — both the success and the error paths. Otherwise an error mid-startup leaks the underlying resource (and for ScreenCaptureKit, keeps the green capture indicator on until process exit). #swift #screencapturekit
- [verification] No tests yet for the OneShotStream double-resume guard — running on macOS 13 hardware would crash the test process before. Manual verification: hit the macOS 13 fallback path. #testing
- [related] Any Apple framework that uses `xxxxOutput`-delegate callbacks (AVFoundation's `AVCaptureVideoDataOutput`, `AVAssetReaderOutput`, Network framework `NWConnection.receive`) has the same multi-fire shape and the same continuation guard requirement.

## Relations

- affects [[Architecture — Client SDK + Optional Relay]]
- prevents_recurrence_of "torn Configuration struct from concurrent configure+read"
- prevents_recurrence_of "Sendable enum carrying Bundle"
- prevents_recurrence_of "CheckedContinuation double-resume crash on macOS 13 screenshot"
