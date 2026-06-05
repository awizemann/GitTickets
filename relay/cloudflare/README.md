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

1. **Custom domain (recommended).** In the Cloudflare dashboard: R2 → `gittickets-attachments` → Settings → Custom Domains → add a subdomain you own (e.g. `attachments.your-app.com`). Then set:
   ```bash
   npx wrangler secret put GITTICKETS_R2_PUBLIC_BASE_URL
   # value: https://attachments.your-app.com
   ```
2. **r2.dev preview URL (dev only).** Enable Public Access in the bucket settings. The URLs work but Cloudflare doesn't guarantee them for production.

The relay's R2 wrapper deliberately uses an `.invalid` host as the fallback when `GITTICKETS_R2_PUBLIC_BASE_URL` is unset — broken images in your issues are loud, not silent.

---

## Setting secrets

```bash
npx wrangler secret put GITHUB_APP_ID
npx wrangler secret put GITHUB_APP_PRIVATE_KEY_BASE64    # base64-wrapped PKCS#8 PEM
npx wrangler secret put GITHUB_INSTALLATION_ID
npx wrangler secret put GITHUB_OWNER
npx wrangler secret put GITHUB_REPO
npx wrangler secret put GITTICKETS_SHARED_SECRET         # openssl rand -hex 32
```

Same private-key conversion gotcha as the Vercel template — `openssl pkcs8 -topk8 -nocrypt` to convert from PKCS#1 to PKCS#8, then `base64 -i private-key-pkcs8.pem`.

---

## Deploying

```bash
npx wrangler deploy
# Note the deploy URL: https://gittickets-relay.<your-account>.workers.dev
```

That URL is what you paste into the Swift SDK's `AuthMode.relay(url:sharedSecret:)`.

---

## Verifying

Same curl recipe as Vercel; just change the URL and use `/report` (not `/api/report`) — though both paths work:

```bash
RELAY_URL=https://gittickets-relay.<your-account>.workers.dev
SECRET=<your-shared-secret-hex>
TIMESTAMP=$(date +%s)
BODY='{"schemaVersion":1,"title":"Smoke","body":"Body long enough to pass spam filter.\n\n<!-- gittickets-id: 11111111-2222-3333-4444-555555555555 -->","labels":["bug"],"submissionID":"11111111-2222-3333-4444-555555555555","deviceID":"smoke","attachmentURLs":[]}'
SIG=$(printf '%s.%s' "$TIMESTAMP" "$BODY" | openssl dgst -sha256 -hmac "$SECRET" -binary | xxd -p -c 256)

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
