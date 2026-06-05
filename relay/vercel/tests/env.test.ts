import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { getEnv, _resetEnvForTests } from "../api/_lib/env.js";

const PKCS8_FIXTURE = `-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQ==\n-----END PRIVATE KEY-----\n`;

function setEnv(values: Record<string, string | undefined>): void {
  for (const [k, v] of Object.entries(values)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
  }
}

beforeEach(() => {
  _resetEnvForTests();
  setEnv({
    GITHUB_APP_ID: "12345",
    GITHUB_APP_PRIVATE_KEY_BASE64: Buffer.from(PKCS8_FIXTURE, "utf8").toString("base64"),
    GITHUB_INSTALLATION_ID: "678",
    GITHUB_OWNER: "alanw",
    GITHUB_REPO: "GitTickets",
    GITTICKETS_SHARED_SECRET: "ab".repeat(32),
    BLOB_READ_WRITE_TOKEN: "tok",
    // Clear optional overrides another test might have set
    GITTICKETS_IP_HOURLY_LIMIT: undefined,
    GITTICKETS_DEVICE_HOURLY_LIMIT: undefined,
    GITTICKETS_ATTACHMENT_BYTE_LIMIT: undefined,
    GITTICKETS_REPLAY_WINDOW_SECONDS: undefined,
    GITTICKETS_LABEL: undefined,
  });
});

afterEach(() => {
  _resetEnvForTests();
});

describe("env loader", () => {
  it("loads all required vars with defaults", () => {
    const env = getEnv();
    expect(env.githubAppId).toBe("12345");
    expect(env.githubInstallationId).toBe("678");
    expect(env.githubOwner).toBe("alanw");
    expect(env.label).toBe("gittickets"); // default
    expect(env.ipHourlyLimit).toBe(30);
    expect(env.attachmentByteLimit).toBe(5_242_880);
    expect(env.replayWindowSeconds).toBe(300);
    expect(env.sharedSecret.length).toBe(32);
  });

  it("throws crisply for missing required var", () => {
    setEnv({ GITHUB_APP_ID: undefined });
    _resetEnvForTests();
    expect(() => getEnv()).toThrow(/GITHUB_APP_ID/);
  });

  it("throws when private key isn't base64-encoded PEM", () => {
    setEnv({
      GITHUB_APP_PRIVATE_KEY_BASE64: Buffer.from("not a PEM file", "utf8").toString("base64"),
    });
    _resetEnvForTests();
    expect(() => getEnv()).toThrow(/PEM/);
  });

  it("rejects negative integer overrides", () => {
    setEnv({ GITTICKETS_IP_HOURLY_LIMIT: "-1" });
    _resetEnvForTests();
    expect(() => getEnv()).toThrow(/GITTICKETS_IP_HOURLY_LIMIT/);
  });

  it("caches across calls", () => {
    const first = getEnv();
    const second = getEnv();
    expect(first).toBe(second);
  });
});
