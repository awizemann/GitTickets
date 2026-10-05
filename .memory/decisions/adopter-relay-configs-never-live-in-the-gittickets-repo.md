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

Decided by Alan 2026-10-05 when ScarfRack (private repo scarfco/ScarfRack) wrote an [env.scarfrack] block into relay/cloudflare/wrangler.toml. GitTickets is public, so that would publish a private product's account, domains and storage IDs. The block was removed uncommitted; ScarfRack got a handoff (documents/handoffs/2026-10-05-scarfrack-relay-config-handoff.md).

## Observations
- [decision] The top-level relay/cloudflare/wrangler.toml is Memophant's deployment only; other adopters keep their own wrangler.toml in their own repo, never as an [env.*] block here #relay
- [convention] Adopters deploy by cloning GitTickets at the pinned SDK tag into a temp dir, copying their config over relay/cloudflare/wrangler.toml, npm ci, wrangler deploy — documented in relay/cloudflare/README.md #relay #deploy
- [fact] GITHUB_OWNER, GITHUB_REPO and GITTICKETS_R2_PUBLIC_BASE_URL are [vars], not secrets; the four secrets are GITHUB_APP_ID, GITHUB_APP_PRIVATE_KEY_BASE64, GITHUB_INSTALLATION_ID, GITTICKETS_SHARED_SECRET #relay
