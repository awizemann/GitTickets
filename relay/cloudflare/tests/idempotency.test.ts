import { afterEach, describe, expect, it } from "vitest";

import {
  lookup,
  record,
  _resetIdempotencyForTests,
} from "../src/lib/idempotency.js";
import type { ParsedEnv } from "../src/lib/env.js";

const env: ParsedEnv = {
  githubAppId: "1",
  githubAppPrivateKey: "",
  githubInstallationId: "1",
  githubOwner: "x",
  githubRepo: "y",
  sharedSecret: new Uint8Array(32),
  label: "gittickets",
  ipHourlyLimit: 30,
  deviceHourlyLimit: 10,
  attachmentByteLimit: 5_242_880,
  replayWindowSeconds: 300,
  r2PublicBaseURL: undefined,
  blob: undefined,
  rateLimitKV: undefined,
  idempotencyKV: undefined,
};

afterEach(() => {
  _resetIdempotencyForTests();
});

describe("idempotency (in-memory fallback)", () => {
  it("returns miss for unknown key", async () => {
    expect((await lookup({ env, key: "k", bodyHash: "h" })).status).toBe("miss");
  });

  it("returns hit for same key + body", async () => {
    await record({ env, key: "k", bodyHash: "h", response: { n: 1 }, now: 0 });
    const result = await lookup({ env, key: "k", bodyHash: "h" });
    expect(result.status).toBe("hit");
    if (result.status === "hit") expect(result.response).toEqual({ n: 1 });
  });

  it("returns conflict for same key + different body", async () => {
    await record({ env, key: "k", bodyHash: "h1", response: { n: 1 }, now: 0 });
    expect((await lookup({ env, key: "k", bodyHash: "h2" })).status).toBe("conflict");
  });

  it("first write wins", async () => {
    await record({ env, key: "k", bodyHash: "h", response: { n: 1 }, now: 0 });
    await record({ env, key: "k", bodyHash: "h", response: { n: 999 }, now: 0 });
    const result = await lookup({ env, key: "k", bodyHash: "h" });
    expect(result.status).toBe("hit");
    if (result.status === "hit") expect(result.response).toEqual({ n: 1 });
  });
});
