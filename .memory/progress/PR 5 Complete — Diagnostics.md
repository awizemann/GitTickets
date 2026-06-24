---
title: PR 5 Complete — Diagnostics
type: note
permalink: gittickets/progress/pr-5-complete-diagnostics
tags:
- progress
- pr-5
- diagnostics
- redaction
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

PR 5 (Diagnostics) shipped 2026-06-04. The collect-and-redact pipeline is live; collector wired in PR 8/12.

## Observations

- [verified] 76/76 tests green on macOS. iOS Sim build clean. #verification
- [files-shipped] `Sources/GitTickets/Diagnostics/` — `RedactionPipeline.swift`, `DeviceInfo.swift`, `OSLogTailer.swift`, `DiagnosticsBlob.swift`, `DiagnosticsCollector.swift`. Plus 3 test files. #files
- [decision] Redaction runs ONCE at the end of `DiagnosticsCollector.collect`. What the user sees (rendered blob) is byte-identical to what gets POSTed. Critical invariant — never re-redact after the user confirms. #invariant
- [decision] `DeviceInfo.humanReadable` falls back to the raw `utsname` identifier for unknown devices, with "Simulator (arch)" wrapper when `SIMULATOR_DEVICE_NAME` env var is set. Better to surface raw than say "unknown". #pattern
- [decision] `OSLogTailer` uses `.currentProcessIdentifier` scope — does NOT require the `com.apple.developer.os.log` entitlement. Only logs the host app emitted are visible. Anything broader is a future opt-in. #osllog #security
- [decision] `OSLogTailer.recentEntries` never throws — returns `[]` on any failure. Diagnostics are best-effort context, not a hard requirement. The submission must succeed even if log tailing fails. #robustness
- [decision] `OSLog` `OSLogEntry` cast filters to `OSLogEntryLog`. Other entry types (`signpost`, `metadata`) are dropped. #osllog
- [decision] `DiagnosticsBlob.sections` is `[(key: String, value: String)]` (tuple array). Tuples aren't auto-Hashable in Swift; implemented manual `==` and `hash(into:)`. Ordered ordered. #pattern
- [decision] Free disk uses `volumeAvailableCapacityForImportantUsageKey` — the same APFS "purgeable-aware" figure Settings shows, not the raw filesystem free space (which is misleadingly large). #ux
- [decision] Memory section reports `ProcessInfo.physicalMemory` total only — true memory pressure on iOS requires `task_info` mach calls with private APIs in many cases. v1 reports total RAM; v2 could refine. #scope
- [footgun-fixed] IPv6 regex updated from `\b(?:[A-F0-9]{1,4}:){2,7}[A-F0-9]{1,4}\b` to `\b[A-F0-9]{0,4}(?::[A-F0-9]{0,4}){2,7}\b` so `::`-zero-compression forms (e.g. `2001:db8::1`) match. Old regex would have LEAKED real IPv6 addresses through redaction. #footgun #security
- [footgun-fixed] `withUnsafePointer(to: &info.machine)` plus reading `info.machine` for capacity inside the closure body triggers Swift's exclusive-access trap. Fix: copy `MemoryLayout.size(ofValue: info.machine)` to a local BEFORE the `withUnsafePointer` call. #footgun
- [device-table-currency] `DeviceInfo.modelTable` is hand-maintained, last updated 2026-06-04. Add new models as they ship; missing entries fall back gracefully to the raw identifier. #maintenance

## Relations

- precedes PR-6-Screenshot
- realizes [[Architecture — Client SDK + Optional Relay]]
- follows [[PR 4 Complete — Storage]]
