---
title: PR 3 Complete — Bodybuilder
type: note
permalink: gittickets/progress/pr-3-complete-bodybuilder
tags:
- progress
- pr-3
- bodybuilder
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

PR 3 (Bodybuilder) shipped 2026-06-04. The markdown assembly + UUID correlation layer is live; submitters in PR 8+ wire to it.

## Observations

- [verified] 35/35 tests green on macOS. iOS Sim build clean. #verification
- [files-shipped] `Sources/GitTickets/Bodybuilder/` — `CorrelationMarker.swift`, `BodyTemplates.swift`, `IssueBodyBuilder.swift`. Plus `UploadedAttachment` struct in `IssueBodyBuilder.swift`. #files
- [decision] Marker format `<!-- gittickets-id: UUID -->`. The space around the UUID is documented but extractor regex tolerates either spacing variant. Format is STABLE across versions — changing it breaks correlation for already-shipped submissions. #wire-format
- [decision] Extractor returns the FIRST matching marker when multiple are present (e.g. if the user copy-pastes from another issue). Documented in code + test. #api
- [decision] Marker is ALWAYS rendered last in the assembled body. Belt-and-suspenders so the extractor regex doesn't trip on stray HTML comments earlier (e.g. embedded in user-pasted markdown). Test `test_markerIsAlwaysLast` enforces. #invariant
- [decision] Diagnostics rendered in a `\`\`\`text` fenced block. Title-cased "### Diagnostics" header. Section omitted entirely when diagnostics blob is nil or whitespace-only. #wire-format
- [decision] Attachments rendered as `![filename](url)` for `image/*` MIME types, `[filename](url)` for others. v1 only ships image attachments through the relay; the link branch is forward-looking. #wire-format
- [decision] Screenshot rendered as `![screenshot](url)` inline AFTER the user body, BEFORE diagnostics. Sets visual context before debug data. #ux
- [decision] `BodyTemplates.defaultLabels` returns `["bug"]`, `["enhancement"]`, `["question"]` per kind. The relay/submitter adds `gittickets` to the final label list. #wire-format
- [decision] `UploadedAttachment` is `internal` (not surfaced in `PublicAPI/`). It's only meaningful after the relay upload step — exposing it to adopters would confuse the API surface. #api

## Relations

- precedes PR-4-Storage
- realizes [[Architecture — Client SDK + Optional Relay]]
- follows [[PR 2 Complete — Public API Skeleton]]
- depends_on [[Footgun — No Public GitHub Attachment API]]
