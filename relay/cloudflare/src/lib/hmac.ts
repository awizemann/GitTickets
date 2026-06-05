/**
 * HMAC-SHA256 over the canonical `<timestamp>.<body>` input, using Web Crypto
 * (no node:crypto in Workers). Byte-for-byte equivalent to the Vercel +
 * Swift implementations.
 */

export interface VerifyArgs {
  rawBody: Uint8Array;
  timestamp: string;
  signature: string;
  secret: Uint8Array;
  now: number;
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

const SIGNATURE_PREFIX = "sha256=";

export async function verifySignature(args: VerifyArgs): Promise<VerifyResult> {
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

  const expectedHex = await computeHex(args.timestamp, args.rawBody, args.secret);
  const expectedBytes = hexToBytes(expectedHex);
  const candidateBytes = hexToBytes(candidateHex);
  if (expectedBytes.length !== candidateBytes.length) {
    return { ok: false, reason: "signature_mismatch" };
  }
  let diff = 0;
  for (let i = 0; i < expectedBytes.length; i += 1) {
    diff |= (expectedBytes[i] ?? 0) ^ (candidateBytes[i] ?? 0);
  }
  return diff === 0 ? { ok: true } : { ok: false, reason: "signature_mismatch" };
}

export async function computeHex(
  timestamp: string,
  body: Uint8Array,
  secret: Uint8Array,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    bytesOf(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const encoder = new TextEncoder();
  const ts = encoder.encode(timestamp);
  const dot = encoder.encode(".");
  const input = new Uint8Array(ts.byteLength + dot.byteLength + body.byteLength);
  input.set(ts, 0);
  input.set(dot, ts.byteLength);
  input.set(body, ts.byteLength + dot.byteLength);
  const sig = await crypto.subtle.sign("HMAC", key, bytesOf(input));
  return bytesToHex(new Uint8Array(sig));
}

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    out[i / 2] = Number.parseInt(hex.substring(i, i + 2), 16);
  }
  return out;
}

function bytesToHex(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i += 1) {
    out += (bytes[i] ?? 0).toString(16).padStart(2, "0");
  }
  return out;
}

/** crypto.subtle wants an ArrayBuffer or BufferSource; subarray views are
 *  fine but tests sometimes pass Buffer subclasses that aren't recognized.
 *  Re-wrap in a plain Uint8Array slice to be safe. */
function bytesOf(bytes: Uint8Array): Uint8Array {
  if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
    return bytes;
  }
  return bytes.slice();
}

export { SIGNATURE_PREFIX };
