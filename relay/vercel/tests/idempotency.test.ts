import { afterEach, describe, expect, it } from "vitest";

import {
  lookup,
  record,
  _resetIdempotencyForTests,
} from "../api/_lib/idempotency.js";
import type { Env } from "../api/_lib/env.js";

const env: Env = {
  githubAppId: "1",
  githubAppPrivateKey: "",
  githubInstallationId: "1",
  githubOwner: "x",
  githubRepo: "y",
  sharedSecret: Buffer.alloc(32),
  blobReadWriteToken: "blob",
  label: "gittickets",
  ipHourlyLimit: 30,
  deviceHourlyLimit: 10,
  attachmentByteLimit: 5_242_880,
  replayWindowSeconds: 300,
};

afterEach(() => {
  _resetIdempotencyForTests();
});

describe("idempotency (in-memory)", () => {
  it("returns miss for unknown key", async () => {
    const result = await lookup({ env, key: "key-1", bodyHash: "hash-1" });
    expect(result.status).toBe("miss");
  });

  it("returns hit for same key + same body hash", async () => {
    await record({
      env,
      key: "key-1",
      bodyHash: "hash-1",
      response: { issueNumber: 42 },
      now: 1_000,
    });
    const result = await lookup({ env, key: "key-1", bodyHash: "hash-1" });
    expect(result.status).toBe("hit");
    if (result.status === "hit") {
      expect(result.response).toEqual({ issueNumber: 42 });
    }
  });

  it("returns conflict for same key + different body hash", async () => {
    await record({
      env,
      key: "key-2",
      bodyHash: "hash-1",
      response: { issueNumber: 1 },
      now: 0,
    });
    const result = await lookup({ env, key: "key-2", bodyHash: "hash-different" });
    expect(result.status).toBe("conflict");
  });

  it("first write wins (record is idempotent)", async () => {
    await record({
      env,
      key: "key-3",
      bodyHash: "hash-1",
      response: { issueNumber: 1 },
      now: 0,
    });
    await record({
      env,
      key: "key-3",
      bodyHash: "hash-1",
      response: { issueNumber: 999 },
      now: 0,
    });
    const result = await lookup({ env, key: "key-3", bodyHash: "hash-1" });
    expect(result.status).toBe("hit");
    if (result.status === "hit") {
      expect(result.response).toEqual({ issueNumber: 1 });
    }
  });
});
