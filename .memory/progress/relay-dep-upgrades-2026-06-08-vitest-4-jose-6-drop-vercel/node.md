---
title: Relay dep upgrades 2026-06-08 — vitest 4, jose 6, drop @vercel/node
type: note
permalink: gittickets/progress/relay-dep-upgrades-2026-06-08-vitest-4-jose-6-drop-vercel/node
tags:
- relay
- security
- deps
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

## Outcome
Both relays at **0 vulnerabilities** after this pass (was 14 vercel / 5 cloudflare).

## Changes
**relay/vercel/package.json**
- Removed `@vercel/node` devDep entirely. It was unused — every handler already imports `IncomingMessage`/`ServerResponse` from `node:http`. The dep was dragging in vulnerable `undici 5.28.4`, `path-to-regexp 6.1.0`, `minimatch`, `ajv`, `smol-toml` via `@vercel/build-utils` + `@vercel/static-config`. Even @vercel/node@5.8.14 (latest) still ships those vulnerable transitives. `npm audit fix --force` wanted to **downgrade** 5→3 — wrong direction.
- jose ^5.9 → ^6.2
- vitest ^2.1 → ^4.1

**relay/cloudflare/package.json**
- jose ^5.9 → ^6.2
- vitest ^2.1 → ^4.1
- (wrangler was already on ^4.98)

Both lockfiles regenerated (`rm -rf node_modules package-lock.json && npm install`).

## Verification
- `tsc --noEmit` clean in both
- vitest 4.1.8: vercel 37/37 passing, cloudflare 32/32 passing
- `wrangler deploy --dry-run` clean (Upload 195 KiB / 37 KiB gzip)

## Why the upgrades were safe
- **jose 5→6**: only call sites are `SignJWT` + `importPKCS8` in [vercel](relay/vercel/api/_lib/githubApp.ts) and [cloudflare](relay/cloudflare/src/lib/githubApp.ts). Removed v6 features (Ed448/X448, secp256k1, RSA1_5, JWE zip) aren't used; `KeyObject → CryptoKey` return-type change is invisible because the key is passed straight to `.sign()` which accepts both. Node 20 engines field already satisfies the new Node 19+ floor.
- **vitest 2→4**: no `vitest.config.ts` in either relay (using defaults). Test files use only `describe/it/expect` from `vitest` — none of the breaking-change touchpoints (`workspace`, `UserConfig`, `spyOn`, `test.order`, `environment: 'browser'`, `basic` reporter) appear.

## Observations
- [footgun] `npm audit fix --force` may recommend a major-version DOWNGRADE that re-opens unrelated CVEs. Always check whether the dep is even used before accepting the suggestion.
- [pattern] Vercel Functions don't require `@vercel/node` at runtime — the platform auto-detects the default-exported `(req, res) => ...` handler and provides node:http req/res. The package is only needed for `VercelRequest`/`VercelResponse` types.
