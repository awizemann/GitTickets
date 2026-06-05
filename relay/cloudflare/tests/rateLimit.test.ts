import { afterEach, describe, expect, it } from "vitest";

import {
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
