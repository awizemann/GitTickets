---
title: Footgun — No Anonymous GitHub Write Surface
type: note
permalink: gittickets/footguns/footgun-no-anonymous-git-hub-write-surface
tags:
- footgun
- github-api
- auth
---

There is no way for an unauthenticated end-user to post to GitHub. Every option for "anonymous reporting" is really about *where the auth token lives*.

## Observations

- [fact] Issues REST API, Discussions GraphQL API, and the image-upload CDN all require auth — no anonymous write path exists. #github-api
- [anti-pattern] Embedded PAT in app binary: trivially extractable (`strings`, MachO inspection, MITM the first request). Rotating breaks every shipped build. NEVER ship this. #anti-pattern
- [fact] GitHub App requires RS256-signed JWT to mint installation tokens. The private key cannot live on a client — it MUST live on a server (or behind remote signing via KMS). Drives the relay requirement. #github-app
- [tradeoff] OAuth Device Flow needs no client secret (just client ID) but forces every end-user to have a GitHub account and complete a browser dance. Wrong default for consumer apps; right for developer-targeted apps. #device-flow
- [requirement] Relay token should be a fine-grained GitHub App installation token scoped to `Issues: write` on exactly ONE repo for minimum blast radius. #security

## Relations

- drives [[Architecture — Client SDK + Optional Relay]]
- documented_in [[Wiki — Threat Model]]
