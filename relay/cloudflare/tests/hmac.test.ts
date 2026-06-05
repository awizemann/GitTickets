import { describe, expect, it } from "vitest";

import { computeHex, verifySignature } from "../src/lib/hmac.js";

const SECRET = new Uint8Array(32).fill(0x37);
const NOW = 1_800_000_000;

describe("HMAC (Workers / Web Crypto)", () => {
  it("matches the locked cross-language vector", async () => {
    // Same triple as relay/vercel/tests/hmac.test.ts and Swift's
    // Tests/GitTicketsTests/Auth/RelaySignatureTests.swift
    // test_lockedVectorMatchesRelayImplementations.
    const timestamp = "1700000000";
    const body = new TextEncoder().encode('{"hello":"world"}');
    const hex = await computeHex(timestamp, body, SECRET);
    expect(hex).toBe(
      "54f12328229a172be47ba5bd5383957265a2f482cfa072373e82783f4805b1c6",
    );
  });

  it("rejects mismatched signature", async () => {
    const body = new TextEncoder().encode("hello");
    const timestamp = `${NOW}`;
    const expected = await computeHex(timestamp, body, SECRET);

    const wrong = await verifySignature({
      rawBody: body,
      timestamp,
      signature: `sha256=${"f".repeat(64)}`,
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(wrong.ok).toBe(false);
    if (!wrong.ok) expect(wrong.reason).toBe("signature_mismatch");

    const right = await verifySignature({
      rawBody: body,
      timestamp,
      signature: `sha256=${expected}`,
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(right.ok).toBe(true);
  });

  it("rejects stale timestamp", async () => {
    const old = `${NOW - 1000}`;
    const expected = await computeHex(old, new Uint8Array(), SECRET);
    const result = await verifySignature({
      rawBody: new Uint8Array(),
      timestamp: old,
      signature: `sha256=${expected}`,
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("stale_timestamp");
  });

  it("rejects malformed signature prefix", async () => {
    const result = await verifySignature({
      rawBody: new Uint8Array(),
      timestamp: `${NOW}`,
      signature: "abc",
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("malformed_signature");
  });

  it("rejects malformed timestamp", async () => {
    const result = await verifySignature({
      rawBody: new Uint8Array(),
      timestamp: "garbage",
      signature: `sha256=${"a".repeat(64)}`,
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("malformed_timestamp");
  });
});
