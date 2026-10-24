---
title: Footgun — iOS Sim XCTest Has No Keychain Entitlement
type: note
permalink: gittickets/footguns/footgun-ios-sim-xctest-has-no-keychain-entitlement
tags: [footgun, ios-simulator, keychain, testing, xctest]
source_paths: [Sources/GitTickets/Storage/Keychain.swift, .github/workflows/swift.yml]
source_paths_inferred: true
source_sha: ed614c17366c18af31b5728d8d6a64d03b3745b7
created: 2026-06-06
updated: 2026-07-12
reviewed: 2026-06-24
reviewed_by: human
---

## Observations

- [status] Mitigation in place as of 2026-06-10 (commit 8604751): Keychain tests skip on iOS Sim via `#if targetEnvironment(simulator) && os(iOS)` guard + `XCTSkip` in `setUpWithError()`. The underlying Keychain entitlement limitation persists — this is a workaround pending a longer-term fix. #mitigation
- [fact] Status code `-34018` is `errSecMissingEntitlement`. Same code Apple documents for "Internal error when a required entitlement isn't present." See <https://developer.apple.com/documentation/security/1542001-security_framework_result_codes>. #keychain #ios
- [rule] Don't trust a green `xcodebuild build` for iOS Sim as proof that Keychain-using code works on iOS — the test run is the actual signal, and a SwiftPM-only test target won't have the entitlements. Equivalently: run `xcodebuild test` periodically, not just `xcodebuild build`. #testing
- [fix-option] **Host-app target for unit tests.** Add an empty iOS app target in the test plan with `keychain-access-groups` in its entitlements; XCTest's "test host" is set to that app. Standard Apple pattern but requires moving away from pure SPM tests. #fix
- [implemented] **Skip via `#if !targetEnvironment(simulator)`** — now active across `KeychainTests`, `DeviceIdentityTests`, `TokenStoreTests`, `DeviceFlowSubmitterTests`. Tests skip cleanly on iOS Sim with explicit `XCTSkip` messaging; macOS and real-device coverage unchanged. Implemented 2026-06-10 in commit 8604751. #implemented #fix
- [fix-option] **`kSecUseDataProtectionKeychain: true`.** Apple-recommended modernization that uses the iOS data-protection keychain instead of the file-based keychain. Doesn't always sidestep the entitlement requirement — depends on test bundle code-signing. Worth trying first since it's a one-line change to `Keychain.swift`. #fix
- [verified] Discovered after PR 14 iOS Sim test run: 191 tests executed, 26 failed (all Keychain-related, all `errSecMissingEntitlement`). Post-mitigation (2026-06-10): 198 tests executed, 30 skipped (Keychain tests), 0 failures. My new `GitTicketsViewControllerTests` (2 tests) ran and passed, confirming the new UIKit code itself is fine. #verification
- [warning] CI implications: any GitHub Actions workflow that runs `xcodebuild test` on iOS Sim will pass (tests skip cleanly) but offers no Keychain coverage at that tier. The existing CI workflows (`.github/workflows/swift.yml`, `relay-*.yml`) target macOS swift test + relay vitest, which cover Keychain fully. #ci
- [scope] The Keychain code itself works on real iOS devices — this is purely a test-infrastructure limitation. Don't refactor Keychain.swift trying to "fix" what isn't broken in production. #scope

## Relations

- documented_in [[PR 14 Complete — UIKit Container]]
- mitigated_by commit 8604751 (fix(ci): get Build & Test green on macOS and iOS Simulator)
- related [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]]
- blocks "iOS Sim test parity" (pending host-app target or data-protection keychain implementation)
