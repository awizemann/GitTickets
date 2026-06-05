import { describe, expect, it } from "vitest";

import { computeHex, verifySignature } from "../api/_lib/hmac.js";

const SECRET = Buffer.alloc(32, 0x37); // matches Swift cross-vector test
const NOW = 1_800_000_000;

describe("HMAC", () => {
  it("matches the Swift SDK cross-language vector", () => {
    // Mirror of Tests/GitTicketsTests/Auth/RelaySignatureTests.swift
    // test_signMatchesIndependentHmacComputation: timestamp=1700000000,
    // body bytes=`{"hello":"world"}`, secret=32 bytes of 0x37.
    //
    // The expected output below was computed independently:
    //   node -e 'const c=require("crypto");
    //            const h=c.createHmac("sha256",Buffer.alloc(32,0x37));
    //            h.update(Buffer.from("1700000000.{\"hello\":\"world\"}","utf8"));
    //            console.log(h.digest("hex"))'
    //
    // If this value ever changes the SDK and relay are out of sync — and an
    // already-deployed Swift app will start failing 401 on a fresh relay
    // deploy. NEVER change this constant without a coordinated
    // schemaVersion bump on both sides.
    const timestamp = "1700000000";
    const body = Buffer.from('{"hello":"world"}', "utf8");
    expect(computeHex(timestamp, body, SECRET)).toBe(
      "54f12328229a172be47ba5bd5383957265a2f482cfa072373e82783f4805b1c6",
    );
  });

  it("rejects mismatched signature", () => {
    const body = Buffer.from("hello", "utf8");
    const timestamp = `${NOW}`;
    const expected = computeHex(timestamp, body, SECRET);
    const result = verifySignature({
      rawBody: body,
      timestamp,
      signature: `sha256=${"f".repeat(64)}`,
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("signature_mismatch");
    // sanity: real signature passes
    const ok = verifySignature({
      rawBody: body,
      timestamp,
      signature: `sha256=${expected}`,
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(ok.ok).toBe(true);
  });

  it("rejects stale timestamp", () => {
    const body = Buffer.from("hi", "utf8");
    const old = `${NOW - 1000}`;
    const expected = computeHex(old, body, SECRET);
    const result = verifySignature({
      rawBody: body,
      timestamp: old,
      signature: `sha256=${expected}`,
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("stale_timestamp");
  });

  it("rejects malformed signature prefix", () => {
    const result = verifySignature({
      rawBody: Buffer.from(""),
      timestamp: `${NOW}`,
      signature: "abc",
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("malformed_signature");
  });

  it("rejects malformed timestamp", () => {
    const result = verifySignature({
      rawBody: Buffer.from(""),
      timestamp: "not-a-number",
      signature: `sha256=${"a".repeat(64)}`,
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("malformed_timestamp");
  });

  it("rejects missing headers", () => {
    const result = verifySignature({
      rawBody: Buffer.from(""),
      timestamp: "",
      signature: "",
      secret: SECRET,
      now: NOW,
      replayWindowSeconds: 300,
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("missing_headers");
  });
});
