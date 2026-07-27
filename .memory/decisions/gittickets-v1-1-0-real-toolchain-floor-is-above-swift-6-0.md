---
title: GitTickets v1.1.0 real toolchain floor is above Swift 6.0
type: note
permalink: gittickets/decisions/gittickets-v1-1-0-real-toolchain-floor-is-above-swift-6-0
tags: [swift6, release, ci, toolchain, v1.1.0]
source_paths: [Sources/GitTickets/Screenshot/ScreenshotCapture+macOS.swift, .github/workflows/swift.yml, Package.swift, CHANGELOG.md]
source_paths_inferred: false
source_sha: 51b13d984b453a892dbb4abd4e63281bf62a2fbb
created: 2026-07-25
updated: 2026-07-26
---

v1.1.0 was tagged and pushed on 2026-07-25 (annotated tag on 51b13d9 = origin/main). Verifying CI afterward surfaced that the release's advertised toolchain floor is wrong. The Swift 6 language mode is real, but the package does not compile on the oldest toolchain that supports it. GitHub Actions "Build & Test" pins runs-on: macos-14, whose newest available Xcode is 16.2 (Swift 6.0) — and that compiler rejects code the local Xcode 26.6 (Swift 6.3.3) compiler accepts. Region-based isolation was relaxed after Swift 6.0, so the Task in OneShotStream.capture is an error on 6.0 and fine on 6.3. Consequence: anyone on Xcode 16.x cannot build v1.1.0, despite CHANGELOG, README, docs and the tag annotation all claiming "Xcode 16+".

## Observations
- [gotcha] v1.1.0 does NOT build on Swift 6.0 / Xcode 16.2 despite CHANGELOG, README, docs/getting-started.md and the v1.1.0 tag annotation all claiming minimum toolchain Swift 6.0 (Xcode 16+) — that claim was never verified and is wrong #swift6 #release
- [fact] Single library-target compile error blocks it: Sources/GitTickets/Screenshot/ScreenshotCapture+macOS.swift:88 Task { } — task-isolated value of type () async -> () passed as a strongly transferred parameter. Library target, not tests, so it reaches consumers #swift6
- [fact] Verified green on Xcode 26.6 / Swift 6.3.3: swift build 0 warnings, swift test 210/210. Exact minimum working toolchain between 6.0 and 6.3.3 is NOT verified — no Xcode 16.x locally to bisect #ci
- [gotcha] CI Build & Test has never passed — every run back to 2026-06-04 is red, predating the Swift 6 work, so the red is not a migration regression. The compile error IS new with Swift 6; earlier reds were test-level (NSURLErrorDomain -1009 network access, iOS Sim keychain) #ci
- [constraint] CI cannot validate this package as configured: macos-14 caps Xcode at 16.2 and the iOS destination is pinned to iPhone 15 / OS=17.5. Bump the runner image before trusting any CI signal #ci

## Relations
- relates_to [[Swift 6 Language Mode Migration V1 1 0]]


## Resolved in v2.0.0 (2026-07-26)

RESOLVED. The blocking code was deleted, not repaired, and the false claim was corrected in place.

- The Swift 6.0 error lived in the `OneShotStream` macOS 13 `SCStream` fallback. At the new macOS 14 floor that branch was statically unreachable — the capture path already called `SCScreenshotManager.captureImage` behind `if #available(macOS 14.0, *)` with the identical filter and configuration. So every macOS 14+ user was already on the surviving path in production; v2.0.0 deleted a fallback rather than fixing a live path (net -90 lines).
- CI is now GREEN for the first time in the repository's history (run 30203729406): macOS 210 executed / 6 skipped, iOS 198 executed / 30 skipped, with the iOS job resolving a real iOS 18.6 simulator. Verified on Xcode 26.3 / macos-15.
- v2.0.0 asserts NO minimum Xcode version — only what was built and run. Whether v2.0.0 compiles on Xcode 16.x is still untested in both directions, and the CHANGELOG says so rather than guessing.
- The v1.1.0 CHANGELOG entry now carries an in-place correction block; the original false text is preserved beneath it for the record. The v1.1.0 git tag annotation still contains the false claim and was deliberately NOT moved — moving a published tag is worse than an inaccurate annotation.

The durable process lesson is recorded separately: push the branch, let CI prove the claim, and only then tag. See [[footgun-xcodebuild-test-does-not-forward-env-to-xctest]].
