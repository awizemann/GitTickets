---
title: Footgun — Retry Non-Idempotent POST Without Idempotency Key
type: note
permalink: gittickets/footguns/footgun-retry-non-idempotent-post-without-idempotency-key
tags:
- footgun
- networking
- relay
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

A transport-level retry of a POST (Vercel cold-start returns 504 *after* the relay called the GitHub API; URLSession sees `URLError(.networkConnectionLost)` while the server already processed the request) creates a duplicate GitHub issue.

`URLSession` cannot distinguish "request never sent" from "request sent, response lost" — the transport just throws. A naive retry-on-error loop assumes the former and resubmits, but the second submit is a new POST with the same body.

Discovered in code review of PR 7/8. Even with our HMAC, the relay had no way to dedupe across attempts because no idempotency token was on the wire.

## Observations

- [rule] HTTPClient retries 5xx for ALL methods but retries transport errors ONLY for idempotent methods (GET/HEAD/OPTIONS). POST/PUT/PATCH/DELETE on transport error → throw to the caller. #networking
- [rule] Every POST through the relay client carries an `X-GitTickets-Idempotency-Key` header derived from `submissionID`. Future relay versions can record the key and short-circuit retries. #relay
- [rule] Pre-submission cache lookup: `RelaySubmitter.submit` checks `SubmissionCache.record(submissionID:)` FIRST and returns the cached result if present. Closes the UI double-tap and the SDK-level retry-after-throw windows. #relay
- [defense-in-depth] Even with idempotency headers + caches, dedupe is a layered concern: relay-side replay protection + SDK-side cache + GitHub itself rejecting an exact-marker dup. Don't rely on any single layer. #relay
- [verification] `test_cachedSubmissionIsReturnedWithoutHittingRelay` covers the SDK cache path. The HTTPClient transport-retry rule is enforced structurally — there's no test yet that asserts POST + transport error does NOT retry; should add one. #testing
- [related] [[Footgun — HMAC Signature Stale on Retry]] — sibling issue, both caused by sharing one signed request across attempts.

## Relations

- affects [[Architecture — Client SDK + Optional Relay]]
- prevents_recurrence_of "duplicate GitHub issue from retried POST"
