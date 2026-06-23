---
title: Footgun — iOS Sim XCTest Has No Keychain Entitlement
type: note
permalink: gittickets/footguns/footgun-ios-sim-xctest-has-no-keychain-entitlement
tags:
- footgun
- ios-simulator
- keychain
- testing
- xctest
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

A SwiftPM XCTest bundle running on iOS Simulator via `xcodebuild test` cannot reach the Keychain — every `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete` returns `errSecMissingEntitlement (-34018)`. The same tests pass on macOS via `swift test` and would pass on a real iOS device, but the Sim test bundle has no `keychain-access-groups` entitlement and the unit-test runner doesn't run inside a host app that could supply one.

Discovered during PR 14 verification when iOS Sim XCTest was actually run for the first time (prior sessions only built for iOS Sim, didn't test). 26 tests fail this way as of the discovery: `TokenStoreTests` (6), `KeychainTests` (5), `DeviceIdentityTests` (5 or so), and the submitter tests that internally hit the token store.

## Observations

- [fact] Status code `-34018` is `errSecMissingEntitlement`. Same code Apple documents for "Internal error when a required entitlement isn't present." See <https://developer.apple.com/documentation/security/1542001-security_framework_result_codes>. #keychain #ios
- [rule] Don't trust a green `xcodebuild build` for iOS Sim as proof that Keychain-using code works on iOS — the test run is the actual signal, and a SwiftPM-only test target won't have the entitlements. Equivalently: run `xcodebuild test` periodically, not just `xcodebuild build`. #testing
- [fix-option] **Host-app target for unit tests.** Add an empty iOS app target in the test plan with `keychain-access-groups` in its entitlements; XCTest's "test host" is set to that app. Standard Apple pattern but requires moving away from pure SPM tests. #fix
- [fix-option] **Skip via `#if !targetEnvironment(simulator)`.** Tag Keychain tests so they skip on Sim. Loses Sim coverage entirely; only useful as a stopgap until the host-app target lands. Mark with a clear comment so a future agent doesn't think the tests are dead code. #fix
- [fix-option] **`kSecUseDataProtectionKeychain: true`.** Apple-recommended modernization that uses the iOS data-protection keychain instead of the file-based keychain. Doesn't always sidestep the entitlement requirement — depends on test bundle code-signing. Worth trying first since it's a one-line change to `Keychain.swift`. #fix
- [verified] Discovered after PR 14 iOS Sim test run: 191 tests executed, 26 failed (all Keychain-related, all `errSecMissingEntitlement`). My new `GitTicketsViewControllerTests` (2 tests) ran and passed, confirming the new UIKit code itself is fine. #verification
- [warning] CI implications: any GitHub Actions workflow that runs `xcodebuild test` on iOS Sim will be permanently red against this codebase until the Keychain entitlement is supplied. The existing CI workflows (`.github/workflows/swift.yml`, `relay-*.yml`) target macOS swift test + relay vitest, which are unaffected. Adding iOS test CI before fixing this would create a "26 failures permanently red" badge. #ci
- [scope] The Keychain code itself works on real iOS devices — this is purely a test-infrastructure limitation. Don't refactor Keychain.swift trying to "fix" what isn't broken in production. #scope

## Relations

- documented_in [[PR 14 Complete — UIKit Container]]
- related [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]]
- blocks "iOS Sim test parity"
