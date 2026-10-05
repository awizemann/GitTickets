# Prompt for the ScarfRack session — move the relay config into ScarfRack (2026-10-05)

Paste everything below the line into the ScarfRack session.

---

**From the GitTickets session (Alan's call): the ScarfRack relay config does not go into the GitTickets repo.**

GitTickets is a public repo. The `[env.scarfrack]` block you added to `relay/cloudflare/wrangler.toml` would publish that `scarfco/ScarfRack` exists, the ScarfBox account ID, the domains and the storage IDs. We have removed it from GitTickets' working tree (never committed). GitTickets keeps only the Worker code; each adopting app owns its own deploy config.

**What you need to do in the ScarfRack repo**

1. Add a deploy folder, e.g. `Deploy/relay/`, holding:
   - `wrangler.toml` — your block, rewritten as a **top-level** config (no `[env.scarfrack]` nesting). Your previous block is copied at the bottom of this message for reference. Keep `name = "scarfrack-tickets"` exactly — that is what makes it update the existing Worker, and the four secrets you already set stay attached to that Worker, so nothing needs re-entering. Add `compatibility_date = "2026-06-01"` (match GitTickets' top-level value) and `main = "src/worker.ts"`.
   - `deploy.sh` — fetches the GitTickets relay at a pinned tag into a temp folder, drops your config in, and deploys:
     ```
     set -euo pipefail
     TAG="v2.5.0"   # GitTickets tag; keep in step with the SDK pin in Packages/RackShell/Package.swift
     WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
     git clone --depth 1 --branch "$TAG" https://github.com/awizemann/GitTickets.git "$WORK/gt"
     cp "$(dirname "$0")/wrangler.toml" "$WORK/gt/relay/cloudflare/wrangler.toml"
     cd "$WORK/gt/relay/cloudflare" && npm ci && npx wrangler deploy
     ```
     Pin to the SDK version tag (`v2.5.0`, later `v2.6.0`), not `relay-cloudflare-v1.0.0` — that relay tag is old and predates later relay fixes. The relay and SDK ship from the same repo, so the SDK tag is the matching relay.
2. Run `deploy.sh` once and confirm it reports an update to `scarfrack-tickets` (not a new Worker), then smoke-test: file one test report from ScarfRack and check it lands in `scarfco/ScarfRack` with its screenshot loading from `tickets-files.scarfrack.co`.
3. Secret changes from now on: `npx wrangler secret put <NAME> --name scarfrack-tickets` (no `--env`). Secrets never in chat, files or logs.
4. Commit the deploy folder in ScarfRack.

**Coming next from GitTickets: v2.6.0**
- My Reports shows no GitHub links or "replies live on GitHub" copy when the repo is private (your in-app-only ruling).
- `GitTicketsMyIssuesView` gains an optional close action (`onClose:`); when set, it shows a Done button. You can then drop your own Done bar.
- We'll tell Alan the version when it is tagged. **Note:** Swift Package Manager can only resolve the tag once Alan pushes it to GitHub — don't bump the exact pin until he confirms the push.

**Your previous block (reference only — rewrite as top-level keys):**
```
[env.scarfrack]
name = "scarfrack-tickets"
account_id = "101e8c9c9c5767df9afa267f57f3bfe1"
workers_dev = false
routes = [{ pattern = "tickets.scarfrack.co", custom_domain = true }]

[env.scarfrack.vars]
GITTICKETS_LABEL = "gittickets"
GITTICKETS_IP_HOURLY_LIMIT = "30"
GITTICKETS_DEVICE_HOURLY_LIMIT = "10"
GITTICKETS_ATTACHMENT_BYTE_LIMIT = "5242880"
GITTICKETS_REPLAY_WINDOW_SECONDS = "300"
GITHUB_OWNER = "scarfco"
GITHUB_REPO = "ScarfRack"
GITTICKETS_R2_PUBLIC_BASE_URL = "https://tickets-files.scarfrack.co"

[[env.scarfrack.r2_buckets]]
binding = "BLOB"
bucket_name = "scarfrack-tickets-attachments"

[[env.scarfrack.kv_namespaces]]
binding = "RATE_LIMIT"
id = "741fdf82d9e04a88ae07500338d79a07"

[[env.scarfrack.kv_namespaces]]
binding = "IDEMPOTENCY"
id = "f2b7f338ca5846d083341781fe421c20"
```
