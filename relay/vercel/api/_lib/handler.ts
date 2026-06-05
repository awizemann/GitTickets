/**
 * Shared HTTP helpers used by every endpoint:
 *
 * - rawBody(req): collect the raw request body into a Buffer (we disable
 *   bodyParser so we can sign the bytes byte-for-byte).
 * - sendJSON, sendError: consistent response envelopes.
 * - withAuth(...): the verify-then-rate-limit-then-handler wrapper used by
 *   /report, /attachment, /my-issues.
 */

import type { IncomingMessage, ServerResponse } from "node:http";

import { getEnv, type Env } from "./env.js";
import { verifySignature, type VerifyResult } from "./hmac.js";
import { checkRateLimits } from "./rateLimit.js";
import { log } from "./logger.js";

const MAX_BODY_BYTES = 10 * 1024 * 1024; // 10 MB hard ceiling

export async function rawBody(req: IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let total = 0;
  for await (const chunk of req) {
    const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    total += buf.byteLength;
    if (total > MAX_BODY_BYTES) {
      throw new BodyTooLargeError();
    }
    chunks.push(buf);
  }
  return Buffer.concat(chunks);
}

export class BodyTooLargeError extends Error {
  constructor() {
    super(`Request body exceeds ${MAX_BODY_BYTES} bytes.`);
  }
}

export function sendJSON(
  res: ServerResponse,
  status: number,
  body: unknown,
): void {
  res.statusCode = status;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.end(JSON.stringify(body));
}

export interface ErrorEnvelope {
  error: string;
  message?: string;
  byteLimit?: number;
}

export function sendError(
  res: ServerResponse,
  status: number,
  body: ErrorEnvelope,
): void {
  sendJSON(res, status, body);
}

export interface AuthenticatedRequest {
  env: Env;
  body: Buffer;
  timestamp: string;
  signature: string;
  idempotencyKey: string | null;
  ip: string | null;
}

/** Verifies HMAC + replay window. On success returns the parsed envelope;
 *  on failure writes a 401 to the response and returns null. */
export function authenticate(
  req: IncomingMessage,
  res: ServerResponse,
  body: Buffer,
  now: number,
): AuthenticatedRequest | null {
  const env = getEnv();
  const timestamp = headerValue(req, "x-gittickets-timestamp");
  const signature = headerValue(req, "x-gittickets-signature");
  const idempotencyKey = headerValue(req, "x-gittickets-idempotency-key");
  const ip = clientIP(req);

  const verify: VerifyResult = verifySignature({
    rawBody: body,
    timestamp: timestamp ?? "",
    signature: signature ?? "",
    secret: env.sharedSecret,
    now,
    replayWindowSeconds: env.replayWindowSeconds,
  });
  if (!verify.ok) {
    log("warning", "signature_failed", {
      reason: verify.reason,
      ip,
      hasTimestamp: !!timestamp,
      hasSignature: !!signature,
    });
    sendError(res, 401, {
      error: "signature_mismatch",
      message: `Signature verification failed: ${verify.reason}.`,
    });
    return null;
  }

  return {
    env,
    body,
    timestamp: timestamp ?? "",
    signature: signature ?? "",
    idempotencyKey: idempotencyKey ?? null,
    ip,
  };
}

export async function enforceRateLimits(
  res: ServerResponse,
  auth: AuthenticatedRequest,
  deviceID: string | null,
  now: number,
): Promise<boolean> {
  const result = await checkRateLimits({
    env: auth.env,
    ip: auth.ip,
    deviceID,
    now,
  });
  if (!result.allowed) {
    if (result.retryAfter) {
      res.setHeader("Retry-After", `${result.retryAfter}`);
    }
    sendError(res, 429, {
      error: "rate_limited",
      message: "Hourly limit exceeded.",
    });
    return false;
  }
  return true;
}

function headerValue(req: IncomingMessage, key: string): string | undefined {
  const value = req.headers[key];
  if (Array.isArray(value)) return value[0];
  return value;
}

function clientIP(req: IncomingMessage): string | null {
  const fwd = headerValue(req, "x-forwarded-for");
  if (fwd) return fwd.split(",")[0]?.trim() ?? null;
  return req.socket?.remoteAddress ?? null;
}
