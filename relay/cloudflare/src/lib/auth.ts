/**
 * Authentication + rate-limit middleware. Verifies HMAC + replay window,
 * then runs the per-IP / per-device limiter.
 */

import { verifySignature } from "./hmac.js";
import { checkRateLimits } from "./rateLimit.js";
import { jsonError, rateLimitedResponse } from "./responses.js";
import { log } from "./logger.js";
import type { ParsedEnv } from "./env.js";

export interface AuthOK {
  ok: true;
  body: Uint8Array;
  timestamp: string;
  signature: string;
  idempotencyKey: string | null;
  ip: string | null;
}

export type AuthResult = AuthOK | { ok: false; response: Response };

export async function authenticate(
  request: Request,
  env: ParsedEnv,
  body: Uint8Array,
  now: number,
): Promise<AuthResult> {
  const timestamp = request.headers.get("x-gittickets-timestamp") ?? "";
  const signature = request.headers.get("x-gittickets-signature") ?? "";
  const idempotencyKey = request.headers.get("x-gittickets-idempotency-key");
  const ip = request.headers.get("cf-connecting-ip") ?? request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null;

  const verify = await verifySignature({
    rawBody: body,
    timestamp,
    signature,
    secret: env.sharedSecret,
    now,
    replayWindowSeconds: env.replayWindowSeconds,
  });
  if (!verify.ok) {
    log("warning", "signature_failed", { reason: verify.reason, ip });
    return {
      ok: false,
      response: jsonError(401, "signature_mismatch", `Signature verification failed: ${verify.reason}.`),
    };
  }

  return {
    ok: true,
    body,
    timestamp,
    signature,
    idempotencyKey,
    ip,
  };
}

export async function enforceRateLimits(
  env: ParsedEnv,
  auth: AuthOK,
  deviceID: string | null,
  now: number,
): Promise<Response | null> {
  const result = await checkRateLimits({ env, ip: auth.ip, deviceID, now });
  if (result.allowed) return null;
  return rateLimitedResponse(result.retryAfter ?? 3600);
}
