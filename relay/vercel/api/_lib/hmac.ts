/**
 * HMAC-SHA256 verification of inbound relay requests.
 *
 * Canonical signing input: `<timestamp>.<body>` — period separator (0x2E)
 * between the unix-seconds timestamp string and the raw body bytes.
 *
 * Must match Swift's `RelaySignature.sign(timestamp:body:secret:)` byte-for-byte.
 * The cross-language vector test in `tests/hmac.test.ts` locks this in.
 */

import { createHmac, timingSafeEqual } from "node:crypto";

const SIGNATURE_PREFIX = "sha256=";

export interface VerifyArgs {
  rawBody: Buffer;
  timestamp: string;
  signature: string;
  secret: Buffer;
  now: number; // unix seconds
  replayWindowSeconds: number;
}

export type VerifyResult =
  | { ok: true }
  | {
      ok: false;
      reason:
        | "missing_headers"
        | "malformed_timestamp"
        | "stale_timestamp"
        | "malformed_signature"
        | "signature_mismatch";
    };

/**
 * Verifies a request signature and timestamp. Constant-time on the signature
 * comparison even when the candidate length is wrong (uses a fixed-length
 * compare).
 */
export function verifySignature(args: VerifyArgs): VerifyResult {
  if (!args.timestamp || !args.signature) {
    return { ok: false, reason: "missing_headers" };
  }

  const ts = Number.parseInt(args.timestamp, 10);
  if (!Number.isFinite(ts) || ts <= 0 || `${ts}` !== args.timestamp.trim()) {
    return { ok: false, reason: "malformed_timestamp" };
  }
  if (Math.abs(args.now - ts) > args.replayWindowSeconds) {
    return { ok: false, reason: "stale_timestamp" };
  }

  if (!args.signature.startsWith(SIGNATURE_PREFIX)) {
    return { ok: false, reason: "malformed_signature" };
  }
  const candidateHex = args.signature.slice(SIGNATURE_PREFIX.length);
  if (candidateHex.length !== 64 || !/^[0-9a-f]+$/.test(candidateHex)) {
    return { ok: false, reason: "malformed_signature" };
  }

  const expectedHex = computeHex(args.timestamp, args.rawBody, args.secret);

  // Constant-time compare on 32-byte raw values.
  const expectedBytes = Buffer.from(expectedHex, "hex");
  const candidateBytes = Buffer.from(candidateHex, "hex");
  if (expectedBytes.length !== candidateBytes.length) {
    return { ok: false, reason: "signature_mismatch" };
  }
  if (!timingSafeEqual(expectedBytes, candidateBytes)) {
    return { ok: false, reason: "signature_mismatch" };
  }
  return { ok: true };
}

/** Returns the lowercase hex SHA-256 HMAC over `<timestamp>.<body>`. */
export function computeHex(
  timestamp: string,
  body: Buffer,
  secret: Buffer,
): string {
  const hmac = createHmac("sha256", secret);
  hmac.update(Buffer.from(timestamp, "utf8"));
  hmac.update(Buffer.from(".", "utf8"));
  hmac.update(body);
  return hmac.digest("hex");
}

export { SIGNATURE_PREFIX };
