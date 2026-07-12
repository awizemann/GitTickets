---
title: Footgun — OpenSSL HMAC -hmac Takes Literal Bytes Not Hex
type: note
permalink: gittickets/footguns/footgun-open-ssl-hmac-hmac-takes-literal-bytes-not-hex
tags:
- footgun
- docs
- deployment
- hmac
source_sha: ed614c17366c18af31b5728d8d6a64d03b3745b7
reviewed: 2026-06-24
reviewed_by: human
source_paths: relay/vercel/README.md, relay/cloudflare/README.md
source_paths_inferred: true
---

`openssl dgst -hmac "$SECRET"` treats `$SECRET` as the literal HMAC key bytes — it does NOT hex-decode. If your shared secret is hex (the recommended `openssl rand -hex 32` shape), the Swift SDK (`SharedSecret(hex:)`) and the relay (`decodeSharedSecret`) BOTH hex-decode to 32 raw bytes, but a naive curl recipe using `-hmac "$SECRET"` HMACs with the 64-char ASCII hex string. Result: `signature_mismatch` 401 even though the secrets "match" character-for-character.

## Observations

- [fact] `openssl dgst -hmac "abcd"` uses 4 bytes (`a`, `b`, `c`, `d`). It NEVER hex-decodes. #openssl
- [fact] To pass a hex-encoded key, use `openssl dgst -sha256 -mac HMAC -macopt hexkey:$SECRET -binary`. The `hexkey:` macopt does the decode. #openssl #fix
- [fact] The Swift SDK and both relay templates hex-decode the shared secret to 32 raw bytes before HMACing. #wire-format
- [fact-fixed] `wiki/Relay-Deployment.md`, `relay/vercel/README.md`, and `relay/cloudflare/README.md` curl smoke-test recipes have been updated to use `-mac HMAC -macopt hexkey:`. Anyone following the old recipe would have hit this exact bug. #docs-drift-fixed
- [discovery] Caught during first real Memophant deploy on 2026-06-05. Spent ~20 min on the wrong rabbit hole (trailing newline in vercel env vars, sensitive-value display quirks) before finally adding fingerprint logs to env.ts/hmac.ts. Bodies + canonical inputs matched byte-for-byte; only the HMAC outputs differed → conclusion was the keys were different sizes. #lessons
- [pattern] When debugging HMAC mismatch, log fingerprints in this order: (1) secret raw + secret decoded (verifies key shape), (2) body bytes (verifies transit), (3) canonical signing input (verifies framing). Diff at the first mismatch tells you whether it's a key, body, or framing issue. #debugging
- [verification] After fix: smoke-test posted issue #3 to github.com/awizemann/Memophant/issues/3 with HTTP 200 and `appliedLabels: ["bug","gittickets"]`. End-to-end pipeline confirmed working. #verification

## Relations

- documented_in_remediation [[Memophant Integration Complete — Help → Report an Issue]]
