/**
 * Environment-variable loader with crisp error messages.
 *
 * Reads all configuration once at module load. Throwing here surfaces in the
 * Vercel function logs as a clean "missing GITHUB_APP_ID" rather than an
 * obscure crypto error inside the JWT signer.
 */

interface RequiredEnv {
  githubAppId: string;
  githubAppPrivateKey: string; // decoded PEM, ready for jose.importPKCS8
  githubInstallationId: string;
  githubOwner: string;
  githubRepo: string;
  sharedSecret: Buffer;
  blobReadWriteToken: string;
}

interface OptionalEnv {
  upstashRedisUrl?: string;
  upstashRedisToken?: string;
  label: string;
  ipHourlyLimit: number;
  deviceHourlyLimit: number;
  attachmentByteLimit: number;
  replayWindowSeconds: number;
}

export interface Env extends RequiredEnv, OptionalEnv {}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value || value.trim().length === 0) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return value;
}

function optionalIntEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const parsed = Number.parseInt(raw, 10);
  if (Number.isNaN(parsed) || parsed < 0) {
    throw new Error(
      `${name} must be a non-negative integer (got '${raw}').`,
    );
  }
  return parsed;
}

function decodePrivateKey(base64: string): string {
  let decoded: string;
  try {
    decoded = Buffer.from(base64, "base64").toString("utf8");
  } catch (err) {
    throw new Error(
      "GITHUB_APP_PRIVATE_KEY_BASE64 could not be base64-decoded. " +
        "Did you wrap the .pem file with `base64 -i private-key.pem`?",
    );
  }
  if (
    !decoded.startsWith("-----BEGIN RSA PRIVATE KEY-----") &&
    !decoded.startsWith("-----BEGIN PRIVATE KEY-----")
  ) {
    throw new Error(
      "GITHUB_APP_PRIVATE_KEY_BASE64 is not valid base64-encoded PEM " +
        "(decoded value does not begin with -----BEGIN). " +
        "Re-run `base64 -i private-key.pem | pbcopy` and paste fresh.",
    );
  }
  return decoded;
}

function decodeSharedSecret(raw: string): Buffer {
  // Accept hex (preferred — what `openssl rand -hex 32` outputs) or base64.
  if (/^[0-9a-fA-F]+$/.test(raw) && raw.length % 2 === 0) {
    return Buffer.from(raw, "hex");
  }
  try {
    return Buffer.from(raw, "base64");
  } catch {
    throw new Error(
      "GITTICKETS_SHARED_SECRET must be hex (preferred) or base64.",
    );
  }
}

let cached: Env | undefined;

export function getEnv(): Env {
  if (cached) return cached;

  const env: Env = {
    githubAppId: requireEnv("GITHUB_APP_ID"),
    githubAppPrivateKey: decodePrivateKey(requireEnv("GITHUB_APP_PRIVATE_KEY_BASE64")),
    githubInstallationId: requireEnv("GITHUB_INSTALLATION_ID"),
    githubOwner: requireEnv("GITHUB_OWNER"),
    githubRepo: requireEnv("GITHUB_REPO"),
    sharedSecret: decodeSharedSecret(requireEnv("GITTICKETS_SHARED_SECRET")),
    blobReadWriteToken: requireEnv("BLOB_READ_WRITE_TOKEN"),
    upstashRedisUrl: process.env.UPSTASH_REDIS_REST_URL,
    upstashRedisToken: process.env.UPSTASH_REDIS_REST_TOKEN,
    label: process.env.GITTICKETS_LABEL ?? "gittickets",
    ipHourlyLimit: optionalIntEnv("GITTICKETS_IP_HOURLY_LIMIT", 30),
    deviceHourlyLimit: optionalIntEnv("GITTICKETS_DEVICE_HOURLY_LIMIT", 10),
    attachmentByteLimit: optionalIntEnv("GITTICKETS_ATTACHMENT_BYTE_LIMIT", 5_242_880),
    replayWindowSeconds: optionalIntEnv("GITTICKETS_REPLAY_WINDOW_SECONDS", 300),
  };

  cached = env;
  return env;
}

/** Test-only — clears the cached Env so a vitest can re-read after mutating process.env. */
export function _resetEnvForTests(): void {
  cached = undefined;
}
