---
title: Footgun — Keychain Synchronizable Default Leaks Across iCloud
type: note
permalink: gittickets/footguns/footgun-keychain-synchronizable-default-leaks-across-i-cloud
tags:
- footgun
- security
- storage
- keychain
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

`SecItemCopyMatching` defaults `kSecAttrSynchronizable` to `kSecAttrSynchronizableAny` — a read can match iCloud-synced items written by a sibling install on the user's other Mac/iPhone. `SecItemAdd` defaults to `false` (local-only), so the WRITE is fine but the READ can pick up unexpected items.

Compounding bug: a global Keychain service identifier (`"com.gittickets.device-id"` with no host-bundle namespacing) means two GitTickets-using apps from the same signing team share the same Keychain item on macOS. Per-install rate limit / per-install "My Issues" then collapses across apps and devices.

Discovered in code review of PR 4.

## Observations

- [rule] Every Keychain query (read AND write AND delete) sets `kSecAttrSynchronizable: kCFBooleanFalse` explicitly. Don't rely on platform defaults. #security #storage
- [rule] Service identifier is namespaced by `Bundle.main.bundleIdentifier`: `DeviceIdentity.defaultServicePrefix + "." + bundleID`. Each host app gets its own UUID. #security
- [rule] `DeviceIdentity.init` exposes `accessGroup` and `service` overrides so hosts that DO want cross-app identity (App Group setup) can opt in explicitly. The default is per-app isolation. #security
- [rule] Don't promise "survives reinstall" without wiring an access group — iOS Keychain items for an uninstalled app are purged unless declared in an explicit access group + entitlement (since iOS 10.3). The docstring now says "per-install" instead, and exposes access group plumbing for callers who want the survive-reinstall property. #ios
- [test-pattern] Keychain tests use a per-test random service identifier so they don't collide. See `KeychainTests.setUp`. The same pattern applies to any process-shared resource (UserDefaults suites, file paths). #testing
- [related] [[Footgun — GitHub App Private Key Newline Corruption]] — different storage, but same lesson: never trust a platform default to be what you want, name it explicitly.

## Relations

- affects [[Architecture — Client SDK + Optional Relay]]
- prevents_recurrence_of "device ID collision across same-team apps"
- prevents_recurrence_of "iCloud-Keychain-synced item leaking across user's devices"
