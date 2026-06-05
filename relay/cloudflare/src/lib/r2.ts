/**
 * R2 attachment upload wrapper. Returns a public URL based on either the
 * configured custom-domain base or R2's preview `r2.dev` URL.
 *
 * Operators that care about long-term URL stability should configure
 * `GITTICKETS_R2_PUBLIC_BASE_URL` to a custom domain bound to the bucket.
 */

import type { ParsedEnv } from "./env.js";
import { extensionForMime } from "./payload.js";

export interface UploadArgs {
  bytes: Uint8Array;
  mimeType: string;
  env: ParsedEnv;
  randomKey?: () => string;
}

export interface UploadResult {
  url: string;
  byteCount: number;
}

export type Uploader = (args: UploadArgs) => Promise<UploadResult>;

export const r2BlobUploader: Uploader = async (args) => {
  if (!args.env.blob) {
    throw new R2Error("R2 binding 'BLOB' is not configured.");
  }
  const ext = extensionForMime(args.mimeType);
  const stem = (args.randomKey ?? defaultRandomKey)();
  const key = `gittickets/${stem}.${ext}`;
  await args.env.blob.put(key, args.bytes, {
    httpMetadata: { contentType: args.mimeType },
  });
  const base = args.env.r2PublicBaseURL;
  const url = base
    ? `${base}/${key}`
    : `https://gittickets-r2-preview.example.invalid/${key}`;
  // The preview-URL fallback is intentionally an .invalid host so missing
  // GITTICKETS_R2_PUBLIC_BASE_URL configuration is loud, not silent. Real
  // R2 preview URLs depend on the account; operators must either bind a
  // custom domain (recommended) or use the dashboard-visible r2.dev URL.
  return { url, byteCount: args.bytes.byteLength };
};

function defaultRandomKey(): string {
  // crypto.randomUUID is available in Workers.
  return crypto.randomUUID();
}

export class R2Error extends Error {
  constructor(message: string) {
    super(message);
    this.name = "R2Error";
  }
}
