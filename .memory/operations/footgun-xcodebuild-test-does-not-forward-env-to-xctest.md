---
title: Footgun xcodebuild test does not forward env to XCTest
type: note
permalink: gittickets/operations/footgun-xcodebuild-test-does-not-forward-env-to-xctest
tags: [ci, footgun, xcodebuild, testing, snapshot-testing]
source_paths: [.github/workflows/swift.yml, Tests/GitTicketsTests/UI/SwiftUI/SnapshotTests.swift, .gitignore, Package.swift]
source_paths_inferred: false
source_sha: a49118057b2b4e46ad56b052eadac433a8125319
created: 2026-07-26
updated: 2026-07-26
---

Three CI facts that each cost real debugging time during the v2.0.0 release, all verified by running them rather than reasoning about them. Any future change to .github/workflows/swift.yml or the snapshot suite should be checked against these.

The meta-lesson: a CI guard must be verified through the SAME command CI uses. The env-var guard below passed under `swift test` and was a complete no-op under `xcodebuild test` — verifying with the convenient command would have shipped a fix that did nothing while reporting success.

## Observations
- [gotcha] `xcodebuild test` does NOT forward the job environment into the XCTest process, so the `CI=true` that GitHub Actions sets is invisible to tests. `swift test` DOES inherit it. Pass `TEST_RUNNER_CI: 'true'` — xcodebuild strips the `TEST_RUNNER_` prefix and injects the remainder. Verified: `CI=true xcodebuild test` gave 6 failures / 0 skipped / exit 65; with TEST_RUNNER_CI it gave TEST SUCCEEDED / 6 skipped #ci #footgun
- [gotcha] swift-snapshot-testing reports a FIRST-RUN recording as a FAILURE ("No reference was found on disk. Automatically recorded snapshot"), not a pass. Since baselines are gitignored and CI is always a clean checkout, the snapshot suite was 6 deterministic red tests on every CI run — not a vacuous pass. Do not assume record-on-missing means green #ci #testing
- [fact] GitHub runner images as of 2026-07: macos-14 is deprecated and caps at Xcode 16.2 (Swift 6.0); macos-26 ships iOS 26.x runtimes ONLY. macos-15 is the sole current image still shipping an iOS 18.x runtime (18.5/18.6), so it is required to test AT an iOS 18 floor rather than only above it. Confirmed in CI: the iOS job resolved a real iOS 18.6 simulator #ci
- [convention] Pin `xcode-version` explicitly instead of `latest-stable`. Floating is how the Swift 6.0 concurrency breakage sat unnoticed for weeks — the toolchain moved with no commit to blame. A pin makes compiler changes a reviewable edit #ci #convention
- [gotcha] A .gitignore pattern containing a slash is anchored to the repo root, so `__Snapshots__/*` plus a negation silently stops ignoring nested baselines. Use `**/`. Also: SPM warns `Invalid Exclude ... File not found` whenever an `exclude:` path is missing, which on a clean checkout it is — keep the directory alive with a committed .gitkeep #footgun

## Relations
- relates_to [[GitTickets v1.1.0 real toolchain floor is above Swift 6.0]]
- relates_to [[Footgun — iOS Sim XCTest Has No Keychain Entitlement]]
