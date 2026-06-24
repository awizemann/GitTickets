---
title: Footgun — HMAC Signature Stale on Retry
type: note
permalink: gittickets/footguns/footgun-hmac-signature-stale-on-retry
tags:
- footgun
- crypto
- networking
- relay
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

If you compute the HMAC `<timestamp>.<body>` signature ONCE before handing the request to a retry loop, every retry replays the same timestamp + signature pair. Two things can break:

1. The relay's clock-skew window (we use 5 minutes) elapses across retries → all attempts after the boundary fail with `401 signatureMismatch`. The user sees a misleading "secret mismatch" error after what was really a transient 5xx.
2. A relay that records `(timestamp, signature)` for replay defense rejects every retry as a replay.

Either way, a transient 5xx looks like a permanent auth failure. Discovered in code review of PR 7/8.

## Observations

- [rule] Re-sign on every retry attempt. `HTTPClient.sendRetrying(buildRequest:)` takes a closure that runs before each attempt; the relay client computes timestamp + signature inside that closure. #networking #crypto
- [rule] Never thread a pre-built signed `URLRequest` through a retry loop. The closure-builder pattern makes "re-sign per attempt" a structural property, not a discipline thing. #networking
- [rule] Idempotency: include `X-GitTickets-Idempotency-Key` on every retry so the relay can dedupe if it ever decides to. The current SDK does this with `submissionID` for `/report`. #relay
- [verification] `Tests/.../RelaySubmitterTests.swift` covers single-attempt path; production retry replays haven't been adversarially tested yet. Add a 5xx-then-200 test that asserts the second attempt's timestamp header differs from the first. #testing
- [related] [[Footgun — Retry Non-Idempotent POST Without Idempotency Key]] — same code path, different failure mode.

## Relations

- affects [[Architecture — Client SDK + Optional Relay]]
- prevents_recurrence_of "transient 5xx surfacing as signatureMismatch"
