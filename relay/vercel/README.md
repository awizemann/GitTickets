# GitTickets relay — Vercel template

A ~10-file Vercel Function deployment that forwards SDK-signed bug reports to a GitHub repo via the GitHub Issues API.

This template implements the [GitTickets relay wire spec](../shared/payload-schema.md). For the Cloudflare Workers variant see [`../cloudflare/`](../cloudflare/).

---

## One-time GitHub App setup

1. Go to **github.com/settings/apps** (or your org's apps page) → **New GitHub App**.
2. **Name**: `<YourApp> Issue Reporter` (must be globally unique).
3. **Homepage URL**: your app's marketing page.
4. **Webhook**: uncheck "Active" — the relay doesn't use webhooks.
5. **Repository permissions** → **Issues: Read & Write**. Nothing else.
6. **Where can this be installed?** → Only on this account.
7. Click **Create**. Note the **App ID** from the General tab.
8. Scroll to **Private keys** → **Generate a private key**. A `.pem` file downloads. Keep it.
9. **Install the App**: left sidebar → **Install App** → select your account → choose **Only select repositories** → pick the one repo issues should land in. Note the **Installation ID** from the URL (`/settings/installations/{ID}`).

### Private key format gotcha

GitHub's downloaded `.pem` is **PKCS#1** (header `-----BEGIN RSA PRIVATE KEY-----`). The relay uses [jose](https://github.com/panva/jose), which requires **PKCS#8** (`-----BEGIN PRIVATE KEY-----`). Convert once:

```bash
openssl pkcs8 -topk8 -nocrypt -in private-key.pem -out private-key-pkcs8.pem
```

Then base64-wrap the PKCS#8 file (line breaks would otherwise get mangled by Vercel's env-var UI):

```bash
base64 -i private-key-pkcs8.pem | pbcopy   # macOS
base64 -w 0 private-key-pkcs8.pem          # Linux
```

The clipboard now holds the value for `GITHUB_APP_PRIVATE_KEY_BASE64`. The relay validates at boot and surfaces clear errors for both wrong-format and corrupted-base64 cases.

---

## Local development

```bash
cd relay/vercel
cp .env.example .env
# Fill in .env with the values from the GitHub App + a fresh shared secret:
#   openssl rand -hex 32
npm install
npm test            # runs vitest
npm run lint        # tsc --noEmit
npx vercel dev      # local function server on http://localhost:3000
```

---

## Deploying

```bash
npx vercel link             # one-time; choose a fresh project
npx vercel env add GITHUB_APP_ID
npx vercel env add GITHUB_APP_PRIVATE_KEY_BASE64
npx vercel env add GITHUB_INSTALLATION_ID
npx vercel env add GITHUB_OWNER
npx vercel env add GITHUB_REPO
npx vercel env add GITTICKETS_SHARED_SECRET
npx vercel env add BLOB_READ_WRITE_TOKEN     # from Vercel dashboard → Storage → Blob → Create
npx vercel deploy --prod
```

The deployment URL is what you paste into the Swift SDK's `AuthMode.relay(url:sharedSecret:)`. The same hex shared secret goes into `SharedSecret(hex: "...")!`.

### Optional: Upstash Redis for rate limiting + idempotency

The relay falls back to per-instance in-memory state when Upstash isn't configured. For multi-region or high-volume deployments add:

```bash
npx vercel env add UPSTASH_REDIS_REST_URL
npx vercel env add UPSTASH_REDIS_REST_TOKEN
```

Without these:
- Rate-limit counts reset when a function instance recycles. Acceptable for low-traffic apps; under-protective for floods that hit cold instances.
- Idempotency is per-instance. A double-tap that gets routed to two different instances could produce two GitHub issues.

---

## Verifying a deployment

```bash
RELAY_URL=https://your-deploy.vercel.app
SECRET=your-shared-secret-hex
TIMESTAMP=$(date +%s)
BODY='{"schemaVersion":1,"title":"Test","body":"Body long enough to pass spam filter.\n\n<!-- gittickets-id: 11111111-2222-3333-4444-555555555555 -->","labels":["bug"],"submissionID":"11111111-2222-3333-4444-555555555555","deviceID":"smoke","attachmentURLs":[]}'
SIG=$(printf '%s.%s' "$TIMESTAMP" "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -binary | xxd -p -c 256)

curl -X POST "$RELAY_URL/api/report" \
  -H "Content-Type: application/json" \
  -H "X-GitTickets-Timestamp: $TIMESTAMP" \
  -H "X-GitTickets-Signature: sha256=$SIG" \
  -H "X-GitTickets-Idempotency-Key: 11111111-2222-3333-4444-555555555555" \
  -d "$BODY"
```

Expected: `200 OK` with `{ "issueNumber": N, "issueURL": "...", "appliedLabels": [...] }`, and an issue appears in your repo within ~2 seconds.

Repeat the same `curl`; the response is identical (idempotency cache hit) and no second issue is created.

---

## Operational knobs

All optional; defaults shown:

| Env var | Default | Notes |
| --- | --- | --- |
| `GITTICKETS_LABEL` | `gittickets` | Label applied to every submission; also the filter for `/my-issues`. |
| `GITTICKETS_IP_HOURLY_LIMIT` | `30` | Per-IP `/report` and `/attachment` cap. |
| `GITTICKETS_DEVICE_HOURLY_LIMIT` | `10` | Per-deviceID cap on `/report` and `/my-issues`. |
| `GITTICKETS_ATTACHMENT_BYTE_LIMIT` | `5242880` (5 MB) | Per-file upload cap. Mirror it on the SDK side for consistent UX. |
| `GITTICKETS_REPLAY_WINDOW_SECONDS` | `300` (5 min) | Signed-timestamp tolerance for clock skew. |

---

## What this template does not do

- **It does not validate that the request is from your real app.** Anyone with the shared secret can submit. The secret IS extractable from your app binary — see `wiki/Threat-Model.md`. Per-IP and per-device rate limits are the real wall. For higher security adopt App Attest / DeviceCheck / Play Integrity attestation tokens in v2.
- **It does not handle GitHub webhooks.** Reply notifications in the SDK use polling.
- **It does not auto-rotate the shared secret.** Plan rotations alongside app releases. Zero-downtime rotation (two secrets accepted simultaneously) is a roadmap item.

---

## Costs

For ~100 reports per day:
- Vercel Hobby: free (well under the function-invocation cap).
- Vercel Blob: ~$0 (a few MB of screenshots).
- Upstash Redis: free tier covers ~10k commands/day.

For higher volume see [Vercel Pricing](https://vercel.com/pricing). The relay does ≤ 3 GitHub API calls per submission (token mint, issue create, optional comment fetch on `/my-issues`) so GitHub rate limits aren't a concern at any realistic SDK volume.
