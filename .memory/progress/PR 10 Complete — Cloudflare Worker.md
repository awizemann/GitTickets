---
title: PR 10 Complete — Cloudflare Worker
type: note
permalink: gittickets/progress/pr-10-complete-cloudflare-worker
tags:
- progress
- pr-10
- relay
- cloudflare
- workers
source_sha: 7a91c04dc0c63debdc49916f60c1b50cfd90c3f6
reviewed: 2026-06-24
reviewed_by: human
---

PR 10 (Cloudflare Worker) shipped 2026-06-05. The relay tier is feature-complete on both supported runtimes; the same HMAC vector locks the contract across all three implementations (Swift SDK + Vercel + Cloudflare).

## Observations

- [verified] 32/32 vitest tests green in `relay/cloudflare/`. `tsc --noEmit` clean. HMAC vector matches Swift + Vercel byte-for-byte. #verification
- [files-shipped] `relay/cloudflare/` (package.json, tsconfig, wrangler.toml, .env.example, README, .gitignore), `src/worker.ts`, `src/handlers/{report,attachment,myIssues}.ts`, `src/lib/{env,hmac,githubApp,payload,rateLimit,idempotency,r2,multipart,github,responses,auth,logger}.ts`, `tests/{hmac,payload,multipart,rateLimit,idempotency,env}.test.ts`. Plus `.github/workflows/relay-cloudflare.yml`. #files
- [decision] Web Crypto (`crypto.subtle`) for HMAC verification — no `node:crypto` dependency, no `nodejs_compat` flag needed. Works on the V8 isolate runtime out of the box. #cloudflare
- [decision] jose 5.x is runtime-agnostic and signs RS256 via Web Crypto on Workers. Same library as Vercel — only the surrounding code differs. #dependencies
- [decision] Multipart parser ported to pure `Uint8Array` (no `Buffer`). The Workers runtime doesn't expose Node Buffer without the compat flag, and porting was ~50 lines. #cloudflare #pattern
- [decision] Router lives in `src/worker.ts` as a switch on `url.pathname`. Accepts both `/foo` and `/api/foo` so a single curl recipe works against both Vercel and CF deployments. No routing library — switch beats `itty-router` for 3 endpoints. #routing
- [decision] R2 URL builder uses an **`.invalid`** host as the fallback when `GITTICKETS_R2_PUBLIC_BASE_URL` is unset. Broken images in your issues are LOUD, not silent — operators notice immediately and configure the custom domain. #defensive
- [decision] KV is eventually consistent across regions, so the rate-limit fetch-increment-put isn't atomic. Documented as: occasional double-grant under flood is preferable to shedding all traffic on contention. Acceptable for an hourly bucket. #tradeoff
- [decision] Per-isolate in-memory fallback for both rate limit and idempotency, so the relay works for `wrangler dev` and ultra-low-volume deploys without provisioning KV. Same fallback strategy as Vercel's in-memory mode. #parity
- [decision] Tests are pure-function unit tests under vitest — no miniflare, no `@cloudflare/vitest-pool-workers`. The lib code accepts env / KV / R2 as injected arguments, so vitest under Node runs them fine. Saves a heavy dev dep. #testing
- [decision] env parser is per-request (`parseEnv(env)` called inside `fetch`). No module-level cache — Workers env is passed per-invocation and may differ across staged deploys. #cloudflare
- [decision] Worker entry catches `EnvError` separately from generic uncaught — env errors return 500 with a hint, generic uncaught returns 500 without details (don't leak internals). #security
- [parity] Wire-format contract proved by `tests/hmac.test.ts` locking the same hex (`54f12328229a172be47ba5bd5383957265a2f482cfa072373e82783f4805b1c6`) the Vercel + Swift tests assert. Three implementations, one contract. #wire-format
- [deployed] **Live since 2026-06-11** at `https://tickets.memophant.co` (Workers custom domain on the `memophant.co` zone), account "Alan Wizemann, LLC". Bindings: R2 `gittickets-attachments` (binding `BLOB`) + custom domain `attachments.memophant.co`; KV `RATE_LIMIT`=`89ec514b477c4e5096bda372bf766580`, KV `IDEMPOTENCY`=`c1e27162af9a4fc69fe7b7d5430713c2`. Secrets: `GITHUB_APP_ID` / `GITHUB_INSTALLATION_ID` / `GITHUB_APP_PRIVATE_KEY_BASE64` (PKCS#8) / `GITTICKETS_SHARED_SECRET`; owner/repo/r2-url are public `[vars]`. Verified end-to-end: signed `POST /my-issues` → 200, wrong-secret control → 401, `attachments.memophant.co` missing-key → R2 404. This is now the production relay for Memophant — the Vercel deployment (`gittickets-memophant`) was deleted. #verification #deployed
- [gotcha] Vercel "Sensitive" env vars can't be read back — `vercel env pull` returns them as empty `KEY=""`. The GitHub App creds for this deploy came from the gitignored local `relay/vercel/.env`, not from Vercel; the shared secret came from the app's `Config/Secrets.local.xcconfig`. #secrets

## Relations

- precedes PR-11-Device-Flow-Submitter
- realizes [[Architecture — Client SDK + Optional Relay]]
- depends_on [[Footgun — GitHub App Private Key Newline Corruption]]
- follows [[PR 9 Complete — Vercel Relay]]
