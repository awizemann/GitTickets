/**
 * GitHub App installation-token minting.
 *
 * Flow:
 *   1. Sign a short-lived JWT (RS256, 10-minute max lifetime) with the App's
 *      private key.
 *   2. Exchange at `POST /app/installations/{id}/access_tokens`.
 *   3. Cache the resulting installation token in-memory until ~50 minutes
 *      before its expiry (tokens live 1 hour).
 *
 * The cache is per Vercel Function instance. Multiple regions / lambdas
 * will each mint their own tokens — acceptable, since GitHub allows ~5k
 * installation token mints/hour per App.
 */

import { SignJWT, importPKCS8 } from "jose";

import type { Env } from "./env.js";

interface CachedToken {
  token: string;
  expiresAt: number; // unix seconds
}

let cached: CachedToken | undefined;

const TOKEN_REFRESH_SECONDS_BEFORE_EXPIRY = 600; // 10 min

export interface MintArgs {
  env: Pick<Env, "githubAppId" | "githubAppPrivateKey" | "githubInstallationId">;
  now: number;
  fetch?: typeof fetch;
}

export async function getInstallationToken(args: MintArgs): Promise<string> {
  if (cached && cached.expiresAt - args.now > TOKEN_REFRESH_SECONDS_BEFORE_EXPIRY) {
    return cached.token;
  }

  const jwt = await signAppJWT(args);
  const httpFetch = args.fetch ?? fetch;
  const response = await httpFetch(
    `https://api.github.com/app/installations/${encodeURIComponent(args.env.githubInstallationId)}/access_tokens`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        Accept: "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "gittickets-relay",
      },
    },
  );

  if (!response.ok) {
    const text = await response.text();
    throw new Error(
      `GitHub /app/installations/.../access_tokens failed (${response.status}): ${text}`,
    );
  }

  const payload = (await response.json()) as { token: string; expires_at: string };
  const expiresAt = Math.floor(new Date(payload.expires_at).getTime() / 1000);
  cached = { token: payload.token, expiresAt };
  return payload.token;
}

/** Signs an RS256 JWT for the App. Exported for tests. */
export async function signAppJWT(args: MintArgs): Promise<string> {
  const key = await importPKCS8(normalizePEM(args.env.githubAppPrivateKey), "RS256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(args.env.githubAppId)
    .setIssuedAt(args.now - 60) // safety margin against clock skew
    .setExpirationTime(args.now + 9 * 60)
    .sign(key);
}

/** jose.importPKCS8 requires the PKCS#8 header. GitHub's downloaded keys
 *  are PKCS#1 (`BEGIN RSA PRIVATE KEY`). Detect and convert via
 *  `importPKCS1` would require a different code path — so the cleanest
 *  route is to require operators upload PKCS#8 (the default for newer
 *  github-app downloads) and surface a clear error otherwise. */
function normalizePEM(pem: string): string {
  if (pem.includes("-----BEGIN PRIVATE KEY-----")) return pem;
  if (pem.includes("-----BEGIN RSA PRIVATE KEY-----")) {
    throw new Error(
      "GitHub App private key is in PKCS#1 (`BEGIN RSA PRIVATE KEY`). " +
        "Convert to PKCS#8 with:\n" +
        "  openssl pkcs8 -topk8 -nocrypt -in private-key.pem -out private-key-pkcs8.pem\n" +
        "Then re-base64-wrap the PKCS#8 file and update GITHUB_APP_PRIVATE_KEY_BASE64.",
    );
  }
  throw new Error("GITHUB_APP_PRIVATE_KEY_BASE64 decoded value does not contain a PEM header.");
}

/** Test-only — clears the cached installation token. */
export function _resetTokenCacheForTests(): void {
  cached = undefined;
}
