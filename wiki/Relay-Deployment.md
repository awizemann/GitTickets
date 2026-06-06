---
title: Relay-Deployment
type: note
permalink: gittickets-wiki/relay-deployment
---

# Relay Deployment

How an adopter spins up the GitTickets relay in front of their GitHub repo. Two parallel templates ship in `/relay/`: Vercel (recommended for most) and Cloudflare Worker (recommended for cold-start sensitivity / R2 permanence).

## One-time setup: create a GitHub App

1. Go to **github.com/settings/apps** (or your org's apps page) → **New GitHub App**.
2. **Name**: `<YourApp> Issue Reporter` (must be globally unique).
3. **Homepage URL**: your app's marketing page.
4. **Webhook**: uncheck "Active" — we don't need webhooks.
5. **Repository permissions** → **Issues: Read & Write**. Nothing else.
6. **Where can this be installed?** → Only on this account.
7. Click **Create**. Note the **App ID** (e.g., `123456`).
8. Generate a **private key** at the bottom of the App settings page. A `.pem` file downloads. Keep it.
9. **Install the App**: in the left sidebar → **Install App** → select your account → choose "Only select repositories" → pick the single repo issues should land in. Note the **Installation ID** from the URL (`/settings/installations/{ID}`).

## Vercel deployment

```bash
cd relay/vercel
cp .env.example .env
# Fill in .env with:
#   GITHUB_APP_ID=...
#   GITHUB_APP_PRIVATE_KEY_BASE64=$(base64 -i /path/to/private-key.pem | pbcopy)
#   GITHUB_INSTALLATION_ID=...
#   GITTICKETS_SHARED_SECRET=$(openssl rand -hex 32)
#   BLOB_READ_WRITE_TOKEN=...      # from Vercel dashboard → Storage → Blob
#   UPSTASH_REDIS_REST_URL=...     # optional; rate limit falls back to in-memory
#   UPSTASH_REDIS_REST_TOKEN=...
npx vercel deploy --prod
```

The deployment URL becomes your `AuthMode.relay(url:)` value. The `GITTICKETS_SHARED_SECRET` becomes your `SharedSecret(hex:)` initializer argument.

### The private key gotcha

PEM files contain literal `\n` line breaks. When you paste a raw PEM into Vercel's env var UI it gets mangled in three different ways depending on your browser. **Always base64-wrap it first.**

```bash
base64 -i private-key.pem | pbcopy   # macOS
base64 -w 0 private-key.pem          # Linux
```

Then paste that single base64 blob as `GITHUB_APP_PRIVATE_KEY_BASE64`. The relay base64-decodes on boot and validates the result begins with `-----BEGIN`.

If you get `GITHUB_APP_PRIVATE_KEY_BASE64 is not valid base64-encoded PEM` at deploy time, the env var got mangled. Re-paste from a fresh `base64 -i` output.

## Cloudflare Worker deployment

```bash
cd relay/cloudflare
cp .env.example .dev.vars
# Fill .dev.vars with the same env vars as Vercel.
npx wrangler login
npx wrangler secret put GITHUB_APP_PRIVATE_KEY_BASE64  # paste base64 blob
npx wrangler secret put GITHUB_APP_ID
npx wrangler secret put GITHUB_INSTALLATION_ID
npx wrangler secret put GITTICKETS_SHARED_SECRET
npx wrangler deploy
```

R2 setup (for attachments):

```bash
npx wrangler r2 bucket create gittickets-attachments
# Edit wrangler.toml to bind the bucket; set public-access in the dashboard.
```

KV setup (for rate limit state):

```bash
npx wrangler kv namespace create RATE_LIMIT
```

## Verifying the deploy

From your laptop:

```bash
RELAY_URL=https://your-deploy.vercel.app
SECRET=your-shared-secret-hex
TIMESTAMP=$(date +%s)
BODY='{"title":"Test","body":"This is a test","kind":"bug","submissionID":"00000000-0000-0000-0000-000000000001","deviceID":"test-device"}'
# Canonical string is "<timestamp>.<body>" — note the literal '.' separator.
# Must match RelaySignature.sign in the Swift SDK byte-for-byte.
SIG=$(printf '%s.%s' "$TIMESTAMP" "$BODY" | openssl dgst -sha256 -mac HMAC -macopt hexkey:$SECRET -binary | xxd -p -c 256)

curl -X POST "$RELAY_URL/report" \
  -H "Content-Type: application/json" \
  -H "X-GitTickets-Timestamp: $TIMESTAMP" \
  -H "X-GitTickets-Signature: sha256=$SIG" \
  -d "$BODY"
```

Expected: `200 OK` with `{ "issueNumber": N, "issueURL": "..." }`, and an issue appears in your repo within ~2 seconds with the `gittickets` and `bug` labels and the HTML comment marker.

## Configuring the Swift app

```swift
GitTickets.configure(.init(
  repo: .init(owner: "alanw", name: "MyApp", visibility: .public),
  auth: .relay(
    url: URL(string: "https://your-deploy.vercel.app")!,
    sharedSecret: SharedSecret(hex: "your-shared-secret-hex")!
  ),
  theme: .default
))
```

## Rate limits

Defaults: 30 reports/hour per IP, 10 reports/hour per device. Tunable via env vars (`GITTICKETS_IP_HOURLY_LIMIT`, `GITTICKETS_DEVICE_HOURLY_LIMIT`). Returns 429 with `Retry-After` header when exceeded.

## Rotating the shared secret

1. Generate a new secret: `openssl rand -hex 32`.
2. Update the relay env var; redeploy.
3. Ship a new app build with the new secret.
4. **Existing installs of the old app stop working.** Plan rotations alongside app releases.

For zero-downtime rotation, support two secrets at once via a comma-separated `GITTICKETS_SHARED_SECRET` env var. Roadmap item; not in v1.0.

---
_Last updated: 2026-06-04 — initial deployment guide_
