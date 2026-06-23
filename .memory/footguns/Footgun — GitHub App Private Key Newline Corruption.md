---
title: Footgun — GitHub App Private Key Newline Corruption
type: note
permalink: gittickets/footguns/footgun-git-hub-app-private-key-newline-corruption
tags:
- footgun
- relay
- deployment
source_sha: 2abeb1abd59498c69229fdb6193ae7b51357f361
reviewed: 2026-06-23
---

The PEM private key has literal `\n` line breaks. When pasted into a Vercel / Cloudflare env var, those newlines get mangled — single-line collapse, escaped `\\n`, or stripped entirely. The relay then fails to mint the installation token with cryptic crypto errors.

## Observations

- [decision] Relay env var is `GITHUB_APP_PRIVATE_KEY_BASE64`, not raw PEM. Always base64-wrapped. #relay #deployment
- [boot-check] Relay validates at startup: base64-decode → assert begins with `-----BEGIN RSA PRIVATE KEY-----` or `-----BEGIN PRIVATE KEY-----`. Crisp error: `"GITHUB_APP_PRIVATE_KEY_BASE64 is not valid base64-encoded PEM"`. #relay
- [docs] README walks through: `base64 -i private-key.pem | pbcopy` on macOS, `base64 -w 0 private-key.pem` on Linux. #docs
- [verification] Manual verification step in PR 9 (Vercel deploy) MUST test the base64-corrupt failure path AND the success path. #testing

## Relations

- prevents_recurrence_of generic-crypto-error-bug
