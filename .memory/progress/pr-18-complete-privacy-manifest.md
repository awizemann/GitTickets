---
title: PR 18 Complete — Privacy Manifest
type: note
permalink: gittickets/progress/pr-18-complete-privacy-manifest
tags:
- progress
- pr-18
- privacy
- app-store
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

PR 18 ships the App Store / Apple-required privacy manifest for the SDK. Adopter-side guidance (how to merge with the host app's own manifest) lands in PR 17's docs.

## Observations

- [verified] 203/203 Swift green. iOS Sim build clean. 37/37 Vercel + 32/32 Cloudflare untouched. #verification
- [shipped] `Sources/GitTickets/PrivacyInfo.xcprivacy` — plist declaring `NSPrivacyTracking=false`, no tracking domains, three collected data types, one required-reasons API. Inline XML comments explain WHY each declaration is there so a future audit doesn't have to re-grep. Declared as a target resource via `.copy("PrivacyInfo.xcprivacy")` in `Package.swift` so the file ships with the SDK bundle. #pr-18
- [audit-driven] Dropped speculative claims from the draft in TASKS.md. The draft mentioned `CrashData`, `PerformanceData`, and `UserDefaults` reasons — `grep` confirmed the SDK uses NONE of these (no crash collection, no perf metrics, no UserDefaults). Declaring categories the SDK doesn't actually use is sloppy at best and Apple-rejectable at worst. Over-declaration costs nothing on review but pollutes the truthfulness signal. #decision
- [declared] Three `NSPrivacyCollectedDataTypes`: (1) `OtherDiagnosticData` for the diagnostics blob (device model, OS version, app version, free disk, OSLog entries), (2) `DeviceID` for the per-install UUID `DeviceIdentity` generates and stores in Keychain — NOT IDFA, NOT identifierForVendor, (3) `PhotosorVideos` for user-attached images (only when the adopter wires the attachment UI; the SDK never opens the photo library on its own). All three: `Linked=false`, `Tracking=false`, `Purpose=AppFunctionality`. #pr-18
- [declared] One `NSPrivacyAccessedAPITypes` entry: `NSPrivacyAccessedAPICategoryDiskSpace` with reason `85F4.1` (display free disk space to the user). Matches `DiagnosticsCollector.freeDiskDescription` which reads `URL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])` to populate the diagnostics blob the user reviews before submitting. #pr-18
- [not-declared] `OSLogStore` — not on Apple's required-reasons API list (OS logging APIs are exempt). `Bundle.main.infoDictionary` reads for app version, `ProcessInfo.processInfo.physicalMemory` for memory readout, `utsname` for device-model lookup — also not on the list. `Date()` is not on the list. `FileManager.default.url(for:)` for the cache directory creation is not on the list. Confirmed by gerp of full Sources/ tree. #scope
- [merge-semantics] When the SDK ships in an adopter's app, Apple's tools merge the SDK's manifest with the host app's manifest. The host's `NSPrivacyTracking` wins (so a host that DOES track keeps tracking=true even though we're false). Adopters need to know that their own manifest must list `PhotosorVideos` if their UI presents the attachment button — the SDK's claim covers our use, but Apple's review wants the app-level manifest to declare what the app does too. PR 17 docs/privacy.md will spell this out. #adopter-guidance
- [defer] `docs/privacy.md` adopter guidance — PR 17 scope. Covers: how Apple merges manifests, what the adopter must add to their own manifest, how to opt out of attachments (and thereby drop the `PhotosorVideos` claim from the relevant chain), how to opt out of OSLog collection. #next

## Relations

- follows [[PR 16 Complete — Theming Polish]]
- enables PR 17 (`docs/privacy.md` covers the adopter-side manifest guidance)
- closes "PR 18 — Privacy manifest" on TASKS.md
