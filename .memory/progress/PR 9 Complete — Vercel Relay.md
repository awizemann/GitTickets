---
title: PR 9 Complete — Vercel Relay
type: note
permalink: gittickets/progress/pr-9-complete-vercel-relay
tags:
- progress
- pr-9
- relay
- vercel
- typescript
---

PR 9 (Vercel relay) shipped 2026-06-05. The TypeScript serverless functions match the locked SDK wire contract; HMAC vector is asserted byte-for-byte on both sides.

## Observations

- [verified] 37/37 vitest tests green. `tsc --noEmit` clean. Cross-language HMAC vector test asserts `sha256=54f12328229a172be47ba5bd5383957265a2f482cfa072373e82783f4805b1c6` for the canonical `("1700000000", `{"hello":"world"}`, 32×0x37)` triple on BOTH sides (Swift + Node). #verification
- [files-shipped] `relay/vercel/` (package.json, tsconfig, vercel.json, .env.example, README.md, .gitignore), `relay/vercel/api/{report,attachment,my-issues}.ts`, `relay/vercel/api/_lib/{env, hmac, githubApp, payload, rateLimit, idempotency, blob, multipart, handler, github, logger}.ts`, `relay/vercel/tests/{hmac,payload,multipart,idempotency,rateLimit,env}.test.ts`, `relay/README.md`, `relay/shared/payload-schema.md`. Plus `.github/workflows/relay-vercel.yml`. #files
- [decision] `bodyParser: false` on every endpoint so we get the raw request bytes for HMAC verification. Body parsed manually in the handler after signature verification passes. Re-parsing after verify makes the trust boundary unambiguous — every byte of computation happens AFTER auth. #security
- [decision] `X-GitTickets-Idempotency-Key` REQUIRED on `/report` (400 otherwise). The SDK passes the submissionID as the key. Closes the race window where a network blip drops the response and the SDK retries — without idempotency the retry creates a second GitHub issue. #idempotency
- [decision] Idempotency `conflict` returns 409 (not 200 with stale response) when the same key arrives with a different body hash. Surfaces the bug instead of masking it. #api
- [decision] PKCS#1→PKCS#8 conversion guidance in the env loader error message. GitHub downloads `.pem` as PKCS#1 (`BEGIN RSA PRIVATE KEY`); `jose.importPKCS8` needs PKCS#8 (`BEGIN PRIVATE KEY`). The error tells operators the exact `openssl pkcs8` command. #footgun
- [decision] MIME whitelist (`image/{png,jpeg,gif,webp,heic}`, `application/octet-stream`, `text/plain`) mirrors the Swift side. Type mismatches between SDK and relay would cause silent server-side rejection. #wire-format
- [decision] Multipart parser is ~70 LOC in-house, not `busboy`. The relay handles at most one file per request and the body is already buffered for HMAC; pulling in disk-staged middleware would add complexity for zero benefit. #dependencies
- [decision] Upstash Redis is `optionalDependencies` + dynamic `import()`. The relay falls back to in-memory rate limiting and idempotency per Vercel Function instance. Documented as acceptable-for-low-volume / under-protective-for-high-volume. #rate-limit
- [decision] Installation token cached in-memory per function instance for 50 minutes (tokens live 1 hour). GitHub allows ~5k mints/hour per App — multiple regions each minting is fine. #github-app
- [decision] /my-issues queries up to 5 pages × 100 issues for the configured label. Matches embedded `<!-- gittickets-id: -->` markers against the request's submissionIDs. Latest-comment fetch is per-match (skipped when `comments == 0`) so the cost scales with matches, not total issues. #performance
- [decision] Logger output is JSON-lines to stdout. Vercel surfaces these in the dashboard with searchable fields. Never logs: private key, shared secret, installation tokens, full request bodies. #logging #security
- [wire-format-locked] Status code mapping matches the Swift side exactly: 400→payload_invalid, 401→signature_mismatch, 409→idempotency_replay_mismatch, 413→attachment_too_large (with `byteLimit` field), 415→unsupported_media_type, 429→rate_limited (with `Retry-After` header), 502→github_error, 500→internal_error. #wire-format
- [test-pattern] `_resetEnvForTests` / `_resetRateLimitForTests` / `_resetIdempotencyForTests` exported from the lib files for test isolation. NOT for production use; clearly named. #testing
- [shared-spec] `relay/shared/payload-schema.md` is the language-agnostic wire spec — anyone implementing a third relay (e.g. AWS Lambda + DynamoDB, GCP Functions + Memorystore) follows that doc, not the Vercel TypeScript. #portability
- [deferred] Real end-to-end deploy + GitHub round-trip verification (plan §13.3) deferred to user — needs them to create a throwaway GitHub App and deploy to Vercel. The cross-language HMAC vector locks in the wire contract until then. #verification

## Relations

- precedes PR-10-Cloudflare-Worker
- realizes [[Architecture — Client SDK + Optional Relay]]
- depends_on [[Footgun — GitHub App Private Key Newline Corruption]]
- depends_on [[Footgun — HMAC Signature Stale on Retry]]
- depends_on [[Footgun — Retry Non-Idempotent POST Without Idempotency Key]]
- depends_on [[Footgun — Multipart Header Injection via Filename and MIME]]
- follows [[PR 1-8 Code Review Complete]]
