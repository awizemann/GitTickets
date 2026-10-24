---
title: Adopter relay configs never live in the GitTickets repo
type: note
permalink: gittickets/decisions/adopter-relay-configs-never-live-in-the-gittickets-repo
tags: [relay, scarfrack, deploy]
source_paths: [relay/cloudflare/wrangler.toml, relay/cloudflare/README.md]
source_paths_inferred: false
source_sha: ea3c613983db0a3e35763ecf808707fb00267a36
created: 2026-10-05
updated: 2026-10-05
---

## Observations
- [decision] The top-level relay/cloudflare/wrangler.toml is Memophant's deployment only; other adopters keep their own wrangler.toml in their own repo, never as an [env.*] block here #relay
- [convention] Adopters deploy by cloning GitTickets at the pinned SDK tag into a temp dir, copying their config over relay/cloudflare/wrangler.toml, npm ci, wrangler deploy — documented in relay/cloudflare/README.md #relay #deploy
- [fact] Public vars (GITHUB_OWNER, GITHUB_REPO, GITTICKETS_R2_PUBLIC_BASE_URL, rate-limit thresholds for write and read operations, attachment byte limit, replay window) are set in [vars]; the four secrets (GITHUB_APP_ID, GITHUB_APP_PRIVATE_KEY_BASE64, GITHUB_INSTALLATION_ID, GITTICKETS_SHARED_SECRET) are set via wrangler secret put #relay

## Relations
