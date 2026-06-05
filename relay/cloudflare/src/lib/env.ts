/**
 * Worker env parser. Unlike Vercel/Node, Cloudflare passes env as the second
 * argument to `fetch(request, env, ctx)` — so this function takes the raw
 * binding object and returns a typed snapshot. No module-level caching: each
 * request gets fresh values, which is what Workers wants anyway (env can
 * differ per script version on staged deploys).
 */

export interface WorkerEnv {
  GITHUB_APP_ID: string;
  GITHUB_APP_PRIVATE_KEY_BASE64: string;
  GITHUB_INSTALLATION_ID: string;
  GITHUB_OWNER: string;
  GITHUB_REPO: string;
  GITTICKETS_SHARED_SECRET: string;
  GITTICKETS_LABEL?: string;
  GITTICKETS_IP_HOURLY_LIMIT?: string;
  GITTICKETS_DEVICE_HOURLY_LIMIT?: string;
  GITTICKETS_ATTACHMENT_BYTE_LIMIT?: string;
  GITTICKETS_REPLAY_WINDOW_SECONDS?: string;
  GITTICKETS_R2_PUBLIC_BASE_URL?: string;

  BLOB?: R2Bucket;
  RATE_LIMIT?: KVNamespace;
  IDEMPOTENCY?: KVNamespace;
}

export interface ParsedEnv {
  githubAppId: string;
  githubAppPrivateKey: string;
  githubInstallationId: string;
  githubOwner: string;
  githubRepo: string;
  sharedSecret: Uint8Array;
  label: string;
  ipHourlyLimit: number;
  deviceHourlyLimit: number;
  attachmentByteLimit: number;
  replayWindowSeconds: number;
  r2PublicBaseURL: string | undefined;
  blob: R2Bucket | undefined;
  rateLimitKV: KVNamespace | undefined;
  idempotencyKV: KVNamespace | undefined;
}

export function parseEnv(env: WorkerEnv): ParsedEnv {
  return {
    githubAppId: requireString(env.GITHUB_APP_ID, "GITHUB_APP_ID"),
    githubAppPrivateKey: decodePrivateKey(
      requireString(env.GITHUB_APP_PRIVATE_KEY_BASE64, "GITHUB_APP_PRIVATE_KEY_BASE64"),
    ),
    githubInstallationId: requireString(env.GITHUB_INSTALLATION_ID, "GITHUB_INSTALLATION_ID"),
    githubOwner: requireString(env.GITHUB_OWNER, "GITHUB_OWNER"),
    githubRepo: requireString(env.GITHUB_REPO, "GITHUB_REPO"),
    sharedSecret: decodeSharedSecret(
      requireString(env.GITTICKETS_SHARED_SECRET, "GITTICKETS_SHARED_SECRET"),
    ),
    label: env.GITTICKETS_LABEL ?? "gittickets",
    ipHourlyLimit: parsePositiveInt(env.GITTICKETS_IP_HOURLY_LIMIT, 30, "GITTICKETS_IP_HOURLY_LIMIT"),
    deviceHourlyLimit: parsePositiveInt(env.GITTICKETS_DEVICE_HOURLY_LIMIT, 10, "GITTICKETS_DEVICE_HOURLY_LIMIT"),
    attachmentByteLimit: parsePositiveInt(env.GITTICKETS_ATTACHMENT_BYTE_LIMIT, 5_242_880, "GITTICKETS_ATTACHMENT_BYTE_LIMIT"),
    replayWindowSeconds: parsePositiveInt(env.GITTICKETS_REPLAY_WINDOW_SECONDS, 300, "GITTICKETS_REPLAY_WINDOW_SECONDS"),
    r2PublicBaseURL: env.GITTICKETS_R2_PUBLIC_BASE_URL?.replace(/\/+$/, ""),
    blob: env.BLOB,
    rateLimitKV: env.RATE_LIMIT,
    idempotencyKV: env.IDEMPOTENCY,
  };
}

function requireString(value: string | undefined, name: string): string {
  if (!value || value.trim().length === 0) {
    throw new EnvError(`Missing required env var: ${name}`);
  }
  return value;
}

function parsePositiveInt(value: string | undefined, fallback: number, name: string): number {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  if (Number.isNaN(parsed) || parsed < 0) {
    throw new EnvError(`${name} must be a non-negative integer (got '${value}').`);
  }
  return parsed;
}

function decodePrivateKey(base64: string): string {
  let decoded: string;
  try {
    decoded = new TextDecoder().decode(base64ToBytes(base64));
  } catch {
    throw new EnvError(
      "GITHUB_APP_PRIVATE_KEY_BASE64 could not be base64-decoded. " +
        "Did you wrap the .pem file with `base64 -i private-key.pem`?",
    );
  }
  if (
    !decoded.startsWith("-----BEGIN RSA PRIVATE KEY-----") &&
    !decoded.startsWith("-----BEGIN PRIVATE KEY-----")
  ) {
    throw new EnvError(
      "GITHUB_APP_PRIVATE_KEY_BASE64 is not valid base64-encoded PEM " +
        "(decoded value does not begin with -----BEGIN).",
    );
  }
  if (decoded.startsWith("-----BEGIN RSA PRIVATE KEY-----")) {
    throw new EnvError(
      "GitHub App private key is in PKCS#1 (`BEGIN RSA PRIVATE KEY`). " +
        "Convert to PKCS#8:\n" +
        "  openssl pkcs8 -topk8 -nocrypt -in private-key.pem -out private-key-pkcs8.pem\n" +
        "Then re-base64-wrap the PKCS#8 file.",
    );
  }
  return decoded;
}

function decodeSharedSecret(raw: string): Uint8Array {
  if (/^[0-9a-fA-F]+$/.test(raw) && raw.length % 2 === 0) {
    return hexToBytes(raw);
  }
  try {
    return base64ToBytes(raw);
  } catch {
    throw new EnvError("GITTICKETS_SHARED_SECRET must be hex (preferred) or base64.");
  }
}

/** Worker-safe base64 decode (atob returns binary string). */
export function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = Number.parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

export class EnvError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EnvError";
  }
}
