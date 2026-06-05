import { describe, expect, it } from "vitest";

import { parseEnv, EnvError, type WorkerEnv } from "../src/lib/env.js";

const PKCS8_FIXTURE = `-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQ==\n-----END PRIVATE KEY-----\n`;

function bytesToBase64(s: string): string {
  // Workers/browsers have btoa; tests run under Node which also has it.
  return btoa(s);
}

function validEnv(overrides: Partial<WorkerEnv> = {}): WorkerEnv {
  return {
    GITHUB_APP_ID: "12345",
    GITHUB_APP_PRIVATE_KEY_BASE64: bytesToBase64(PKCS8_FIXTURE),
    GITHUB_INSTALLATION_ID: "678",
    GITHUB_OWNER: "alanw",
    GITHUB_REPO: "GitTickets",
    GITTICKETS_SHARED_SECRET: "ab".repeat(32),
    ...overrides,
  };
}

describe("parseEnv (Workers)", () => {
  it("parses required vars with defaults", () => {
    const env = parseEnv(validEnv());
    expect(env.githubAppId).toBe("12345");
    expect(env.label).toBe("gittickets");
    expect(env.ipHourlyLimit).toBe(30);
    expect(env.attachmentByteLimit).toBe(5_242_880);
    expect(env.sharedSecret.byteLength).toBe(32);
  });

  it("throws EnvError for missing required var", () => {
    expect(() => parseEnv(validEnv({ GITHUB_APP_ID: "" }))).toThrow(EnvError);
  });

  it("throws for PKCS#1 private key", () => {
    const pkcs1 = `-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----\n`;
    expect(() =>
      parseEnv(validEnv({ GITHUB_APP_PRIVATE_KEY_BASE64: bytesToBase64(pkcs1) })),
    ).toThrow(/PKCS#8/);
  });

  it("strips trailing slashes from r2PublicBaseURL", () => {
    const env = parseEnv(validEnv({ GITTICKETS_R2_PUBLIC_BASE_URL: "https://example.com//" }));
    expect(env.r2PublicBaseURL).toBe("https://example.com");
  });

  it("rejects negative integer overrides", () => {
    expect(() => parseEnv(validEnv({ GITTICKETS_IP_HOURLY_LIMIT: "-1" }))).toThrow(EnvError);
  });
});
