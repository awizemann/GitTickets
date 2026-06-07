# Relay deployment

The relay is a small server (Vercel Function or Cloudflare Worker) that
holds a GitHub App installation token scoped to **Issues: Write** on
exactly one repository. The SDK signs each request to the relay with an
HMAC shared secret; the relay verifies the signature, then forwards to
the GitHub Issues API using its token.

Two reference templates ship in this repo. Pick whichever platform you
already use:

- [`relay/vercel/`](../relay/vercel/) — Node 20 + TypeScript on Vercel.
- [`relay/cloudflare/`](../relay/cloudflare/) — TypeScript on Cloudflare
  Workers + R2 for attachments + KV for rate-limit/idempotency.

Both templates implement the same wire contract (see
[`relay/shared/payload-schema.md`](../relay/shared/payload-schema.md)) and
have parity coverage in their respective READMEs:

- [Vercel README](../relay/vercel/README.md)
- [Cloudflare README](../relay/cloudflare/README.md)

Each README walks through:

1. Creating a GitHub App with the correct scopes.
2. Generating an installation token + the private key.
3. Generating the HMAC shared secret with `openssl rand -hex 32`.
4. Setting environment variables on the platform.
5. Deploying.
6. The `curl` smoke test that confirms the relay is talking to GitHub.

## Picking between Vercel and Cloudflare

Both templates work. Differences worth knowing:

| Aspect              | Vercel                                    | Cloudflare Workers                      |
| ------------------- | ----------------------------------------- | --------------------------------------- |
| Attachment storage  | Vercel Blob (90-day TTL on free tier)     | R2 (no expiry)                          |
| Rate-limit / idempotency | Upstash Redis or in-memory          | KV namespaces or in-memory              |
| Cold-start latency  | Slower for the first request after idle   | Sub-ms                                  |
| Free tier           | Generous for low-volume                   | Generous for low-volume                 |

For attachment durability past 90 days, Cloudflare is the recommended
choice. For Node-native tooling familiarity, Vercel is simpler.

## After deployment

Plug the deployed URL + shared secret into your app's `Configuration` —
see [`getting-started.md`](getting-started.md) step 3. The first real
submission should land as an issue in your repo within a few seconds.

## Common deployment failures

- **`401 signatureMismatch`** — the shared secret in the relay's env vars
  doesn't match what the SDK was configured with. The relay uses HMAC-SHA256
  over the raw request bytes; if the secret differs by a single hex digit,
  every request 401s. When verifying with `openssl dgst -hmac <secret>`,
  remember that `openssl`'s `-hmac` flag takes the *literal bytes* of the
  argument, not its hex-decoded value — pass the unhexed secret if your
  config holds hex.
- **`401 from GitHub`** — the App's installation token doesn't have
  `Issues: Write` on the target repo, or the App isn't installed on that
  repo. Recheck the GitHub App settings page.
- **`PEM read error`** — the private key env var has unescaped newlines.
  See the Vercel README's "PKCS#1 → PKCS#8" note. The standard fix is to
  base64-encode the PEM file as the env value, then decode at boot.
