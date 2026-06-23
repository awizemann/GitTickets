---
title: PR 11 Complete — Device Flow Submitter
type: note
permalink: gittickets/progress/pr-11-complete-device-flow-submitter
tags:
- progress
- pr-11
- device-flow
- auth
- oauth
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

PR 11 ships the second production `IssueSubmitter` — the GitHub Device Flow path that lets end-users author issues with their own account, no developer-hosted relay needed. Closes the auth tier; the form work in PR 12 can now hook a discrete `.deviceFlowNotAuthorized` error into the OAuth sheet.

## Observations

- [verified] 165/165 Swift tests green (was 134 — +31 new). 37/37 Vercel + 32/32 Cloudflare untouched and re-confirmed green. iOS Sim build clean. #verification
- [shipped] `Sources/GitTickets/Auth/DeviceFlow/` — four files: `DeviceFlowPayloads.swift` (Codable wire DTOs + `FormURLEncoded` since GitHub's device-code endpoint rejects JSON), `TokenStore.swift` (Keychain wrapper, bundle-id-namespaced like `DeviceIdentity` so two same-team apps don't share a token), `DeviceFlowCoordinator.swift` (hand-rolled state machine), `DeviceFlowSubmitter.swift` (`IssueSubmitter` conformer). #pr-11
- [shipped] `DeviceFlowCoordinator` state machine handles all four documented outcomes plus malformed responses: `authorization_pending` (continue at current interval, take server's fresh interval if larger), `slow_down` (RFC 8628 §3.5 — bump by 5s, take server interval if larger), `expired_token` → `.deviceFlowExpired`, `access_denied` → `.deviceFlowDenied`, unknown error / missing-both-fields → `.payloadInvalid`. Independent wall-clock cutoff at `expiresAt` so an abandoned browser doesn't spin forever — the server keeps returning `authorization_pending` indefinitely without a client-side timeout. `sleep` + `clock` are injected closures so tests fast-forward. #state-machine
- [shipped] `DeviceFlowSubmitter` mirrors `RelaySubmitter` step-for-step: title validation, cache dedupe by `submissionID`, body build via shared `IssueBodyBuilder` (with `screenshotURL=nil`, `attachments=[]`), cache upsert. Headers: `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`. Reuses `RelaySubmitter.missingLabels` so dropped-labels semantics match across both submitters (the `nil` → "unknown" convention specifically). #pr-11
- [decision] Attachments are rejected pre-flight with `.attachmentNotSupportedInDeviceFlow` — `report.screenshot != nil || !report.attachments.isEmpty` short-circuits before any HTTP. Matches the existing `[[Footgun — No Public GitHub Attachment API]]` rule: no public upload endpoint + no relay-side storage in Device Flow mode = no images. PR 12's form must hide the attach button when `auth == .deviceFlow`. #decision
- [decision] New error case `GitTicketsError.deviceFlowNotAuthorized` — distinct from `.deviceFlowDenied` (user said no), `.deviceFlowExpired` (code expired), `.deviceFlowPending` (transient). Means "no token in Keychain yet OR token revoked." Used by submitter when `TokenStore.read()` returns nil AND when GitHub returns 401 (token revoked) — in the 401 case the dead token is `delete()`d so the next submit re-prompts cleanly. Adopters' forms catch this discrete case and drive `DeviceFlowCoordinator`. #api
- [shape-match-avoided] `GitTickets.resolveSubmitter` was wired to `DeviceFlowSubmitter` in the same commit as the submitter itself — the very pattern the [[Audit Pass 2 — Post-Submit-Wiring Sweep]] note warned about ("infrastructure exists but public-API dispatch never reached it"). `test_deviceFlowDispatchReachesSubmitter` locks the wiring: configures `.deviceFlow`, calls `submit()` with no token, expects `.deviceFlowNotAuthorized` — proves dispatch hit the real submitter, not a throwing stub. #pattern
- [scope] `DeviceFlowSubmitter` inherits the protocol's throwing default for `fetchMyIssues` / `fetchReplies`. PR 15's task explicitly mentions "Device Flow `creator=@me`" — that's where the override lands. Not a footgun this time because the protocol default at least throws a clear error string; PR 15 will swap it for a real GitHub-search-API implementation. #scope
- [test-pattern] `AtomicCounter` helper in `DeviceFlowCoordinatorTests.swift` for multi-poll handlers — lets a single `MockURLProtocol.handlers[url]` closure return different responses across calls (call 1 → `authorization_pending`, call 2 → `access_token`). Worth lifting to a shared test helper if more tests need it. #testing
- [test-pattern] `TokenStoreTests.test_distinctHostBundlesGetDistinctTokens` is the explicit regression-lock for the bundle-id-namespacing rule from [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]]. Mirrors `DeviceIdentityTests` for the same property. #testing
- [defer] PR 12 (SwiftUI form) is the natural next pick — it wires `DeviceFlowCoordinator` + `TokenStore` to `ASWebAuthenticationSession` with `verificationURIComplete` + ephemeral session per [[Footgun — iOS Device Flow Return-to-App UX]]. The submitter is ready to receive whatever token the form persists. #next
- [defer] Real-device GitHub round-trip verification deferred — like PR 9 and PR 10, this needs a real OAuth App registered on GitHub and a physical iPhone for the ASWebAuthSession UX (simulator behavior for that API is unreliable). PR 19 / §13.5 of the original plan owns the verification. #verification

## Relations

- follows [[Audit Pass 2 — Post-Submit-Wiring Sweep]]
- enables [[PR 12 Complete — SwiftUI Form]] (future)
- respects [[Footgun — Keychain Synchronizable Default Leaks Across iCloud]]
- respects [[Footgun — No Public GitHub Attachment API]]
- respects [[Footgun — iOS Device Flow Return-to-App UX]]
- closes "PR 11 — Device Flow submitter" on TASKS.md
