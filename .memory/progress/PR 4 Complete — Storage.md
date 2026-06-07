---
title: PR 4 Complete — Storage
type: note
permalink: gittickets/progress/pr-4-complete-storage
tags:
- progress
- pr-4
- storage
- sqlite
- keychain
---

PR 4 (Storage) shipped 2026-06-04. Local persistence is live — Keychain wrapper, stable device identifier, SQLite cache for Phase 2.

## Observations

- [verified] 54/54 tests green on macOS. iOS Sim build clean. #verification
- [files-shipped] `Sources/GitTickets/Storage/` — `Keychain.swift`, `DeviceIdentity.swift`, `SubmissionRecord.swift`, `SubmissionCache.swift`. Plus 3 test files. #files
- [decision] Keychain items use `kSecAttrAccessibleAfterFirstUnlock` — survive reboots, unreadable until device is unlocked at least once. Safer than `Always` (no biometric prompt needed but still encrypted at rest). #keychain #security
- [decision] Keychain.write does SecItemUpdate first; on `errSecItemNotFound` falls back to SecItemAdd. Atomic-feeling upsert without race conditions. #pattern
- [decision] `DeviceIdentity` is a struct (not enum) so tests can inject a unique `(service, account)` per test. Production callers use the zero-arg init. #testability
- [decision] `SubmissionCache` uses the system `SQLite3` module, not SQLite.swift — zero production deps stays intact. Direct C API via Swift's `OpaquePointer` for the db + statement handles. Pattern: prepare → bind → step → finalize. #dependencies
- [decision] `SubmissionCache` is `@unchecked Sendable` with an internal serial `DispatchQueue`. All public methods dispatch onto the queue synchronously. Simpler than an actor under tools-version 5.9. #concurrency
- [decision] Schema is migrated lazily on open via `CREATE TABLE IF NOT EXISTS`. Idempotent. v1 has a single table; future migrations get a `schema_version` PRAGMA pattern. #schema
- [decision] `latest_reply_at` is the only nullable column. Other dates persist as REAL `timeIntervalSince1970`. NULL handling tested explicitly. #schema
- [decision] Index on `submitted_at DESC` so `allRecords()` queries (the My Issues list) don't need to sort in Swift. #performance
- [pattern] `Binding` enum (`text / int / double / null`) wraps the SQLite C bind APIs so the call sites read like Swift instead of `sqlite3_bind_*` salad. #pattern
- [decision] `SubmissionRecord.body` IS cached locally for offline detail-view rendering. Risk: full markdown bodies can be a few KB each. Acceptable — submission counts are bounded by user volume. #tradeoff
- [decision] `delete(submissionID:)` and `deleteAll()` exist primarily for tests; production has no "forget my submissions" flow in v1. Document if a user-facing wipe-my-history feature is requested. #scope
- [gotcha] `XCTAssertEqual(..., accuracy:)` doesn't accept Optional — must `XCTUnwrap` first. Hit this on `latestReplyAt?.timeIntervalSince1970`. #footgun

## Relations

- precedes PR-5-Diagnostics
- realizes [[Architecture — Client SDK + Optional Relay]]
- follows [[PR 3 Complete — Bodybuilder]]
