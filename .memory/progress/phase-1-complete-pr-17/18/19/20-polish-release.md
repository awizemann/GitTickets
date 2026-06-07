---
title: Phase 1 Complete — PR 17 / 18 / 19 / 20 Polish + Release
type: note
permalink: gittickets/progress/phase-1-complete-pr-17/18/19/20-polish-release
tags:
- progress
- pr-17
- pr-18
- pr-19
- pr-20
- phase-1
- release
- v1.0.0
---

Phase 1 is feature-complete and release-prepped. Four PRs landed in one pass: docs (PR 17), privacy manifest (PR 18), example apps (PR 19), and release prep (PR 20). User runs the actual `git tag` + `git push --tags` when ready.

## Observations

- [verified] 203/203 Swift, 37/37 Vercel, 32/32 Cloudflare, iOS Sim build clean across all four PRs. No regressions. #verification
- [shipped-pr-18] `Sources/GitTickets/PrivacyInfo.xcprivacy` declared as a target resource (`.copy(...)` in `Package.swift`). Three collected data types (`OtherDiagnosticData`, `DeviceID`, `PhotosorVideos` — all `Linked=false / Tracking=false / Purpose=AppFunctionality`) plus one required-reasons API (`DiskSpace` reason `85F4.1`). Audit-driven: dropped speculative `CrashData` / `PerformanceData` / `UserDefaults` claims from the draft after `grep` confirmed zero use. Per-section comments explain WHY each claim is there so a future audit doesn't have to re-grep. #pr-18
- [shipped-pr-19] `Examples/` with three reference-code integrations: `MacSampleApp/MacSampleApp.swift` (SwiftUI Mac, `GitTicketsCommands` + Window scene), `iOSSampleApp/iOSSampleApp.swift` (SwiftUI iOS, sheet presentation), `AppKitSampleApp/AppKitSampleApp.swift` (pure AppKit, factory + ReportWindowController.shared). `Examples/README.md` with a host-shape → directory → wired-surfaces table. No standalone `.xcodeproj` skeletons — the format is fragile across Xcode versions and the integration code itself is the value. #pr-19
- [shipped-pr-17] 8 doc files under `docs/`: `getting-started.md` (auth-mode picker → install → configure → wire), `relay-deployment.md` (deep-link to templates + common 401 / PEM failure modes inline), `device-flow.md` (when/when-not + OAuth App setup + user-flow + token revocation), `theming.md` (every theme field with default/effect table + `GitTicketsImageSource` cases), `diagnostics.md` (policy + opt-outs + OSLog + custom redactors), `privacy.md` (manifest declarations + adopter merge guidance + per-claim opt-outs), `threat-model.md` (protects-against / does-not-cover / compliance posture), `architecture.md` (ASCII data flow + two auth-mode dispatch summary + submission pipeline). Root `README.md` stale `GitTicketsCommands()` example replaced with the closure form + sheet pattern; doc links swapped from `wiki/` → `docs/`. #pr-17
- [shipped-pr-20] Release source-prep: `UserAgent.sdkVersion` bumped `1.0.0-dev` → `1.0.0`; `CHANGELOG.md` v1.0.0 entry covering the SDK + relay-template change set (Added — SDK / Added — Relay templates / Status sections); root README "Status" replaced with the shipped-state line + CHANGELOG/TASKS pointers. Tag execution left to user — TASKS.md item now lists the exact commands. #pr-20
- [docs-decision] Adopter-facing docs DO NOT cross-reference `.memory/footguns/` paths. Older footgun filenames carry em-dashes + spaces that don't URL-resolve cleanly across markdown renderers, and adopters shouldn't have to dig into contributor-only memory tier anyway. Where a specific gotcha is worth mentioning, it's inlined into the doc directly (e.g. `openssl -hmac` literal-vs-hex in `relay-deployment.md`, redactor over-match warning in `diagnostics.md`). #docs
- [docs-pattern] Each doc is 60–180 lines, tight, single-purpose. The `getting-started.md` is the entry point everything else links back to. Mutual cross-references between docs are abundant — the goal is that an adopter following any one doc has clear links to the others they'll need. #docs
- [examples-decision] Treating Examples/ as copy-paste reference code (single `.swift` file per host shape + README placeholders) rather than buildable standalone projects. Buildable `.xcodeproj`s would require hand-writing the project format or shipping XcodeGen specs — both fragile and version-coupled. The reference code is the value; adopters create their own project and paste it in. Documented this rationale in `Examples/README.md`. #scope
- [release-decision] Tagging is user-action: source is release-ready but `git tag` + `git push` go through the user. The TASKS.md release item now lists the exact commands. Matches the AGENTS.md guidance about not committing / pushing without explicit ask. #release
- [scope-deferred] Phase 2 (PR 15, "My Issues" view) stays in TODO — the user explicitly asked for "Phase 1 completely first" so we held off. The infrastructure for it is already shipped (`SubmissionCache`, `fetchMyIssues` / `fetchReplies` on both submitters, `MyIssuesPolicy`); PR 15 is the UI on top. #next
- [scope-deferred] iOS Sim Keychain entitlement failures (TASKS.md item) — orthogonal test infrastructure issue discovered during PR 14, deferred per scope discussion. #next
- [scope-deferred] Relay README screenshots from a clean walkthrough — needs a real GitHub App creation flow which is user-action-dependent. Mentioned in TASKS.md release line but not blocking the tag. #next

## Relations

- follows [[PR 16 Complete — Theming Polish]]
- closes Phase 1 of TASKS.md (PRs 1–20 except 15 which is Phase 2)
- enables v1.0.0 tag-and-push when user is ready
- precedes PR 15 (My Issues view, Phase 2)
