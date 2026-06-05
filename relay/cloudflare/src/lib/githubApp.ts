/**
 * GitHub App installation-token minting on Workers. Same flow as the Vercel
 * template but Web-Crypto-native via jose's edge build.
 */

import { SignJWT, importPKCS8 } from "jose";

import type { ParsedEnv } from "./env.js";

interface CachedToken {
  token: string;
  expiresAt: number;
}

// Per-isolate cache. Workers reuse isolates across requests, so this is
// shared within a region while it lives. Cold starts re-mint.
let cached: CachedToken | undefined;

const TOKEN_REFRESH_SECONDS_BEFORE_EXPIRY = 600;

export interface MintArgs {
  env: Pick<ParsedEnv, "githubAppId" | "githubAppPrivateKey" | "githubInstallationId">;
  now: number;
  fetchFn?: typeof fetch;
}

export async function getInstallationToken(args: MintArgs): Promise<string> {
  if (cached && cached.expiresAt - args.now > TOKEN_REFRESH_SECONDS_BEFORE_EXPIRY) {
    return cached.token;
  }
  const jwt = await signAppJWT(args);
  const fetchFn = args.fetchFn ?? fetch;
  const response = await fetchFn(
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
  cached = {
    token: payload.token,
    expiresAt: Math.floor(new Date(payload.expires_at).getTime() / 1000),
  };
  return payload.token;
}

export async function signAppJWT(args: MintArgs): Promise<string> {
  const key = await importPKCS8(args.env.githubAppPrivateKey, "RS256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(args.env.githubAppId)
    .setIssuedAt(args.now - 60)
    .setExpirationTime(args.now + 9 * 60)
    .sign(key);
}

export function _resetTokenCacheForTests(): void {
  cached = undefined;
}
