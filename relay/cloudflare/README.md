# GitTickets relay — Cloudflare Workers template

A Worker that implements the [GitTickets relay wire spec](../shared/payload-schema.md). Same endpoints, same HMAC scheme, same idempotency semantics as the [Vercel template](../vercel/) — different runtime.

When to choose this over Vercel:

- **Permanent attachment URLs.** Bind a custom domain to an R2 bucket for stable image links in your GitHub issues. Vercel Blob preview URLs are time-limited on the free tier.
- **Cold-start sensitivity.** Workers cold-start in ~5ms.
- **You already run Cloudflare.** Single pane of glass for DNS, WAF, and the relay.

---

## GitHub App setup

Identical to the Vercel template — see [`../vercel/README.md` § One-time GitHub App setup](../vercel/README.md#one-time-github-app-setup). The same `.pem` file works here.

---

## Local development

```bash
cd relay/cloudflare
cp .env.example .dev.vars
# Fill .dev.vars with the values from your GitHub App + a fresh shared secret.
npm install
npm test
npm run lint
npx wrangler dev   # local Worker on http://localhost:8787
```

---

## Provisioning bindings

```bash
# 1. R2 bucket for attachments
npx wrangler r2 bucket create gittickets-attachments

# 2. KV namespaces for rate-limit + idempotency state
npx wrangler kv namespace create RATE_LIMIT
npx wrangler kv namespace create IDEMPOTENCY
```

Both `kv namespace create` calls print an ID. Paste them into `wrangler.toml`:

```toml
[[r2_buckets]]
binding = "BLOB"
bucket_name = "gittickets-attachments"

[[kv_namespaces]]
binding = "RATE_LIMIT"
id = "<id from CLI>"

[[kv_namespaces]]
binding = "IDEMPOTENCY"
id = "<id from CLI>"
```

### R2 public access

Workers can put bytes into R2, but external clients (GitHub's image renderer) need a public URL. Two options:

1. **Custom domain (recommended).** In the Cloudflare dashboard: R2 → `gittickets-attachments` → Settings → Custom Domains → add a subdomain you own (e.g. `attachments.your-app.com`). Then set it under `[vars]` in `wrangler.toml` (it is public, not a secret):
   ```toml
   GITTICKETS_R2_PUBLIC_BASE_URL = "https://attachments.your-app.com"
   ```
2. **r2.dev preview URL (dev only).** Enable Public Access in the bucket settings. The URLs work but Cloudflare doesn't guarantee them for production.

The relay's R2 wrapper deliberately uses an `.invalid` host as the fallback when `GITTICKETS_R2_PUBLIC_BASE_URL` is unset — broken images in your issues are loud, not silent.

---

## Setting secrets

```bash
npx wrangler secret put GITHUB_APP_ID
npx wrangler secret put GITHUB_APP_PRIVATE_KEY_BASE64    # base64-wrapped PKCS#8 PEM
npx wrangler secret put GITHUB_INSTALLATION_ID
npx wrangler secret put GITTICKETS_SHARED_SECRET         # openssl rand -hex 32
```

`GITHUB_OWNER`, `GITHUB_REPO` and `GITTICKETS_R2_PUBLIC_BASE_URL` are public and live in `[vars]` in `wrangler.toml`, not as secrets.

Same private-key conversion gotcha as the Vercel template — `openssl pkcs8 -topk8 -nocrypt` to convert from PKCS#1 to PKCS#8, then `base64 -i private-key-pkcs8.pem`.

---

## Deploying

```bash
npx wrangler deploy
```

Requires Node 22+ (wrangler 4's floor). With `workers_dev = false` and a custom-domain route, the relay URL is that route, e.g. `https://tickets.your-app.com`. That URL is what you paste into the Swift SDK's `AuthMode.relay(url:sharedSecret:)`.

---

## Deploying the relay for another app

The `wrangler.toml` in this directory is the maintainer's own deployment. If your app adopts GitTickets, don't add your configuration here — no accounts, domains, KV/R2 IDs, or repo names, and not as a wrangler `[env.*]` block either. Keep the config in your app's repo and deploy this template from a pinned tag.

**1. Your own `wrangler.toml`**, as a top-level config (not an environment):

```toml
name = "your-app-relay"
main = "src/worker.ts"
compatibility_date = "2026-06-01"   # match this repo's wrangler.toml
account_id = "<your account ID>"
workers_dev = false
routes = [{ pattern = "tickets.your-app.com", custom_domain = true }]

[vars]
GITHUB_OWNER = "your-org"
GITHUB_REPO = "your-app"
GITTICKETS_R2_PUBLIC_BASE_URL = "https://attachments.your-app.com"
GITTICKETS_LABEL = "gittickets"
GITTICKETS_IP_HOURLY_LIMIT = "30"
GITTICKETS_DEVICE_HOURLY_LIMIT = "10"
GITTICKETS_ATTACHMENT_BYTE_LIMIT = "5242880"
GITTICKETS_REPLAY_WINDOW_SECONDS = "300"

# Your own bucket + namespaces — see "Provisioning bindings" above.
[[r2_buckets]]
binding = "BLOB"
bucket_name = "your-app-attachments"

[[kv_namespaces]]
binding = "RATE_LIMIT"
id = "<id from CLI>"

[[kv_namespaces]]
binding = "IDEMPOTENCY"
id = "<id from CLI>"
```

**2. Deploy from a pinned tag.** The relay ships in the same repo as the Swift SDK, so the SDK version tag you depend on is the matching relay:

```bash
#!/usr/bin/env bash
set -euo pipefail

TAG="v2.6.0"                                   # the GitTickets SDK version your app uses
CONFIG="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null && pwd)/wrangler.toml"
[[ -f "$CONFIG" ]] || { echo "no wrangler.toml next to this script" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone --depth 1 --branch "$TAG" https://github.com/awizemann/GitTickets.git "$WORK/GitTickets"
cp "$CONFIG" "$WORK/GitTickets/relay/cloudflare/wrangler.toml"

cd "$WORK/GitTickets/relay/cloudflare"
npm ci
npx wrangler deploy
```

**3. Secrets are per Worker.** Set the four secrets from [Setting secrets](#setting-secrets) against your own config, so the Worker name and account come from it (run from a checkout of `relay/cloudflare`, e.g. the clone the script makes, or anywhere wrangler is installed):

```bash
npx wrangler secret put GITHUB_APP_ID                 --config path/to/your/wrangler.toml
npx wrangler secret put GITHUB_APP_PRIVATE_KEY_BASE64 --config path/to/your/wrangler.toml
npx wrangler secret put GITHUB_INSTALLATION_ID        --config path/to/your/wrangler.toml
npx wrangler secret put GITTICKETS_SHARED_SECRET      --config path/to/your/wrangler.toml
```

Generate a fresh `GITTICKETS_SHARED_SECRET` for each app. Never reuse another deployment's.

**4. Bind the R2 custom domain** to your bucket as in [R2 public access](#r2-public-access), and point `GITTICKETS_R2_PUBLIC_BASE_URL` at it. Skip this and uploads still succeed, but every image link in your issues is broken (it points at an `.invalid` host).

---

## Verifying

Same curl recipe as Vercel; just change the URL and use `/report` (not `/api/report`) — though both paths work:

```bash
RELAY_URL=https://tickets.your-app.com   # your custom-domain route
SECRET=<your-shared-secret-hex>
TIMESTAMP=$(date +%s)
BODY='{"schemaVersion":1,"title":"Smoke","body":"Body long enough to pass spam filter.\n\n<!-- gittickets-id: 11111111-2222-3333-4444-555555555555 -->","labels":["bug"],"submissionID":"11111111-2222-3333-4444-555555555555","deviceID":"smoke","attachmentURLs":[]}'
# The shared secret is hex; the relay and Swift SDK both HMAC with the
# DECODED 32 bytes. -macopt hexkey:$SECRET handles the decode for us.
SIG=$(printf '%s.%s' "$TIMESTAMP" "$BODY" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$SECRET -binary | xxd -p -c 256)

curl -X POST "$RELAY_URL/report" \
  -H "Content-Type: application/json" \
  -H "X-GitTickets-Timestamp: $TIMESTAMP" \
  -H "X-GitTickets-Signature: sha256=$SIG" \
  -H "X-GitTickets-Idempotency-Key: 11111111-2222-3333-4444-555555555555" \
  -d "$BODY"
```

Expected: `200` with `{ "issueNumber": N, "issueURL": "...", "appliedLabels": [...] }`, and an issue appears in your repo within ~1 second.

Repeat the same curl; the response is identical (idempotency cache hit) and no second issue is created. Tail the Worker logs in another terminal:

```bash
npx wrangler tail
```

---

## What's different from Vercel

| Concern | Vercel | Cloudflare |
| --- | --- | --- |
| Crypto | `node:crypto` | Web Crypto (`crypto.subtle`) |
| Attachment storage | Vercel Blob | R2 |
| Rate-limit / idempotency | Upstash Redis (optional) | Workers KV |
| Cold-start | ~200ms first request | ~5ms |
| Local dev | `vercel dev` | `wrangler dev` |
| Logs | Dashboard / `vercel logs` | `wrangler tail` |
| Cost (low volume) | Hobby tier covers it | Workers Free tier covers 100k req/day |

The HMAC, payload, MIME whitelist, multipart parser, and status code mapping are identical. The wire contract test (`tests/hmac.test.ts`) locks in the same vector both runtimes (and the Swift SDK) must produce.
