---
title: PR 8 Complete — Relay Submitter
type: note
permalink: gittickets/progress/pr-8-complete-relay-submitter
tags:
- progress
- pr-8
- relay
- wire-format
- hmac
source_sha: ed614c17366c18af31b5728d8d6a64d03b3745b7
reviewed: 2026-06-24
reviewed_by: human
source_paths: Sources/GitTickets/Auth/IssueSubmitter.swift
source_paths_inferred: true
---

PR 8 (Relay submitter) shipped 2026-06-04. The full Swift-side submission pipeline is live. PR 9 (Vercel relay) implements the server side to match this contract.

## Observations

- [verified] 109/109 tests green on macOS. iOS Sim build clean. #verification
- [files-shipped] `Sources/GitTickets/Auth/IssueSubmitter.swift` + `Auth/Relay/{RelayPayload, RelaySignature, RelayClient, RelaySubmitter}.swift`. Added `diagnosticsBlob: String?` to `Report` in `PublicAPI/Models.swift`. #files
- [wire-format] **HMAC canonical input is `"<timestamp>.<body>"`** — timestamp first, period separator, then JSON body. The relay's Node + CF implementations MUST reproduce this exact string concatenation. Period is `0x2E` (ASCII), no spaces, body is the JSON bytes as sent. #wire-format #relay
- [wire-format] Signature header: `X-GitTickets-Signature: sha256=<lowercase hex>`. Timestamp header: `X-GitTickets-Timestamp: <unix-seconds-integer>`. #wire-format
- [wire-format] JSON encoder uses `.sortedKeys` + `.withoutEscapingSlashes`. Sorted keys make signing deterministic for any given payload. Without-escaping-slashes makes URLs in the body markdown human-readable. #wire-format
- [wire-format] `RelayReportRequest` includes `schemaVersion: 1` so the relay can reject mismatched SDK versions. Bumped only on breaking changes. #wire-format
- [wire-format] Attachment endpoint uses multipart/form-data with a single `file` part. Boundary is `gittickets-<UUID>`. HMAC signs the full multipart body. #wire-format
- [decision] `RelayClient.validate` maps status codes to typed `GitTicketsError`: 401→signatureMismatch, 413→attachmentTooLarge, 429→rateLimited(retryAfter from header), other non-2xx→relayRejected with decoded `error/message` from envelope when available. #pattern
- [decision] `RelaySubmitter.submit` uploads screenshot first, then other attachments, BEFORE assembling the body — the body needs the returned URLs inlined as markdown image links. Order is sequential not concurrent: errors short-circuit the rest. #flow
- [decision] `Report.diagnosticsBlob: String?` is the pre-redacted text the user reviewed in the form. The submitter inlines it VERBATIM into the body and NEVER re-collects diagnostics at submit time. Critical "what user sees == what gets sent" invariant — documented loudly in the doc comment. #invariant
- [decision] Cache upsert is **best-effort** (`try? cache?.upsert`). A SQLite write failure must not fail an otherwise-successful submission. The user got an issue created on GitHub; losing the local cache entry is a degraded but tolerable state. #robustness
- [decision] `RelaySubmitter.init(configuration:cache:userAgent:clock:)` is failable — returns `nil` when `configuration.auth` is not `.relay`. There's also a non-failable init that accepts a pre-built `RelayClient` for tests. #api
- [decision] Title validation: empty after `trimmingCharacters(in: .whitespacesAndNewlines)` → `payloadInvalid`. Body length validation deferred to PR 12 (form-level UX). #scope
- [pattern] `JSON encoding strategy` is hoisted to `RelayJSON.encoder/decoder` static lets so all relay code paths share the same configuration. #pattern

## Relations

- precedes PR-9-Vercel-Relay
- realizes [[Architecture — Client SDK + Optional Relay]]
- depends_on [[Footgun — GitHub App Private Key Newline Corruption]]
- follows [[PR 7 Complete — Networking Core]]
