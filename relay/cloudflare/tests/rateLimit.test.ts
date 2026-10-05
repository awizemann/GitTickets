import { afterEach, describe, expect, it } from "vitest";

import {
  bucketsFor,
  ENDPOINT_RATE_LIMIT_KIND,
  checkRateLimits,
  _resetRateLimitForTests,
} from "../src/lib/rateLimit.js";
import type { ParsedEnv } from "../src/lib/env.js";

const env: ParsedEnv = {
  githubAppId: "1",
  githubAppPrivateKey: "",
  githubInstallationId: "1",
  githubOwner: "x",
  githubRepo: "y",
  sharedSecret: new Uint8Array(32),
  label: "gittickets",
  ipHourlyLimit: 3,
  deviceHourlyLimit: 2,
  readIpHourlyLimit: 4,
  readDeviceHourlyLimit: 3,
  attachmentByteLimit: 5_242_880,
  replayWindowSeconds: 300,
  r2PublicBaseURL: undefined,
  blob: undefined,
  rateLimitKV: undefined,
  idempotencyKV: undefined,
};

afterEach(() => {
  _resetRateLimitForTests();
});

describe("rate limit (in-memory fallback)", () => {
  it("allows traffic under the IP limit", async () => {
    const now = 1_000;
    for (let i = 0; i < 3; i += 1) {
      const result = await checkRateLimits({ env, ip: "1.2.3.4", deviceID: null, now });
      expect(result.allowed).toBe(true);
    }
  });

  it("blocks past the IP limit", async () => {
    const now = 1_000;
    for (let i = 0; i < 3; i += 1) {
      await checkRateLimits({ env, ip: "5.5.5.5", deviceID: null, now });
    }
    const blocked = await checkRateLimits({ env, ip: "5.5.5.5", deviceID: null, now });
    expect(blocked.allowed).toBe(false);
    expect(blocked.retryAfter).toBeGreaterThan(0);
  });

  it("blocks past the device limit even from different IPs", async () => {
    const now = 1_000;
    await checkRateLimits({ env, ip: "1.1.1.1", deviceID: "abc", now });
    await checkRateLimits({ env, ip: "2.2.2.2", deviceID: "abc", now });
    const blocked = await checkRateLimits({ env, ip: "3.3.3.3", deviceID: "abc", now });
    expect(blocked.allowed).toBe(false);
  });

  it("resets when the hour window elapses", async () => {
    const start = 1_000;
    for (let i = 0; i < 3; i += 1) {
      await checkRateLimits({ env, ip: "9.9.9.9", deviceID: null, now: start });
    }
    const later = await checkRateLimits({ env, ip: "9.9.9.9", deviceID: null, now: start + 3601 });
    expect(later.allowed).toBe(true);
  });
});

describe("rate limit: read and write buckets are independent", () => {
  // Fixture: writes allow 2/device + 3/IP; reads allow 3/device + 4/IP. The
  // limits differ on purpose so a shared bucket (or swapped limits) fails.
  it("uses distinct keys for read and write buckets", () => {
    const write = bucketsFor({ env, ip: "1.2.3.4", deviceID: "d", kind: "write" });
    const read = bucketsFor({ env, ip: "1.2.3.4", deviceID: "d", kind: "read" });
    expect(write).toEqual([
      { key: "ip:1.2.3.4", limit: 3 },
      { key: "dev:d", limit: 2 },
    ]);
    expect(read).toEqual([
      { key: "rip:1.2.3.4", limit: 4 },
      { key: "rdev:d", limit: 3 },
    ]);
  });

  it("defaults to the write bucket when kind is omitted", async () => {
    const now = 1_000;
    await checkRateLimits({ env, ip: null, deviceID: "legacy", now });
    await checkRateLimits({ env, ip: null, deviceID: "legacy", now });
    const third = await checkRateLimits({ env, ip: null, deviceID: "legacy", kind: "write", now });
    expect(third.allowed).toBe(false);
  });

  it("reads exhausting the device read bucket don't block a subsequent report", async () => {
    const now = 1_000;
    for (let i = 0; i < 3; i += 1) {
      const r = await checkRateLimits({ env, ip: null, deviceID: "dev-r", kind: "read", now });
      expect(r.allowed).toBe(true);
    }
    const readBlocked = await checkRateLimits({ env, ip: null, deviceID: "dev-r", kind: "read", now });
    expect(readBlocked.allowed).toBe(false);
    expect(readBlocked.retryAfter).toBeGreaterThan(0);

    const report = await checkRateLimits({ env, ip: null, deviceID: "dev-r", kind: "write", now });
    expect(report.allowed).toBe(true);
  });

  it("reads exhausting the IP read bucket don't block a subsequent report", async () => {
    const now = 1_000;
    for (let i = 0; i < 4; i += 1) {
      await checkRateLimits({ env, ip: "7.7.7.7", deviceID: null, kind: "read", now });
    }
    const readBlocked = await checkRateLimits({ env, ip: "7.7.7.7", deviceID: null, kind: "read", now });
    expect(readBlocked.allowed).toBe(false);

    const report = await checkRateLimits({ env, ip: "7.7.7.7", deviceID: "dev-ip", kind: "write", now });
    expect(report.allowed).toBe(true);
  });

  it("writes exhausting their buckets don't block reads", async () => {
    const now = 1_000;
    await checkRateLimits({ env, ip: "8.8.8.8", deviceID: "dev-w", kind: "write", now });
    await checkRateLimits({ env, ip: "8.8.8.8", deviceID: "dev-w", kind: "write", now });
    const writeBlocked = await checkRateLimits({ env, ip: "8.8.8.8", deviceID: "dev-w", kind: "write", now });
    expect(writeBlocked.allowed).toBe(false);

    const read = await checkRateLimits({ env, ip: "8.8.8.8", deviceID: "dev-w", kind: "read", now });
    expect(read.allowed).toBe(true);
  });

  it("read device limit honours readDeviceHourlyLimit, not deviceHourlyLimit", async () => {
    const custom = { ...env, readDeviceHourlyLimit: 5 };
    const now = 1_000;
    for (let i = 0; i < 5; i += 1) {
      const r = await checkRateLimits({ env: custom, ip: null, deviceID: "dev-c", kind: "read", now });
      expect(r.allowed).toBe(true);
    }
    const blocked = await checkRateLimits({ env: custom, ip: null, deviceID: "dev-c", kind: "read", now });
    expect(blocked.allowed).toBe(false);
  });

  it("read IP limit honours readIpHourlyLimit, not ipHourlyLimit", async () => {
    const custom = { ...env, readIpHourlyLimit: 6 };
    const now = 1_000;
    for (let i = 0; i < 6; i += 1) {
      const r = await checkRateLimits({ env: custom, ip: "6.6.6.6", deviceID: null, kind: "read", now });
      expect(r.allowed).toBe(true);
    }
    const blocked = await checkRateLimits({ env: custom, ip: "6.6.6.6", deviceID: null, kind: "read", now });
    expect(blocked.allowed).toBe(false);
  });
});

describe("endpoint -> rate-limit bucket mapping", () => {
  it("routes writes to the write bucket and reads to the read bucket", () => {
    expect(ENDPOINT_RATE_LIMIT_KIND).toEqual({
      "/report": "write",
      "/attachment": "write",
      "/my-issues": "read",
      "/comments": "read",
    });
  });
});

describe("zero limits", () => {
  it("a read IP limit of 0 blocks reads but not writes", async () => {
    const closed = { ...env, readIpHourlyLimit: 0 };
    const now = 1_000;
    const read = await checkRateLimits({ env: closed, ip: "4.4.4.4", deviceID: null, kind: "read", now });
    expect(read.allowed).toBe(false);
    const write = await checkRateLimits({ env: closed, ip: "4.4.4.4", deviceID: null, kind: "write", now });
    expect(write.allowed).toBe(true);
  });
});
