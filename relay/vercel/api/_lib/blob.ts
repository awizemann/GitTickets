/**
 * Vercel Blob attachment upload wrapper. Tests inject a fake uploader so the
 * Blob SDK is never invoked in CI.
 */

import { extensionForMime } from "./payload.js";

export interface UploadArgs {
  bytes: Buffer;
  mimeType: string;
  token: string;
  randomKey?: () => string; // overridable for deterministic tests
}

export interface UploadResult {
  url: string;
  byteCount: number;
}

export type Uploader = (args: UploadArgs) => Promise<UploadResult>;

/** Default uploader using @vercel/blob. */
export const vercelBlobUploader: Uploader = async (args) => {
  const { put } = (await import("@vercel/blob")) as {
    put: (
      path: string,
      body: Buffer,
      opts: {
        access: "public";
        token: string;
        contentType: string;
        addRandomSuffix?: boolean;
      },
    ) => Promise<{ url: string }>;
  };

  const ext = extensionForMime(args.mimeType);
  const stem = (args.randomKey ?? defaultRandomKey)();
  const result = await put(`gittickets/${stem}.${ext}`, args.bytes, {
    access: "public",
    token: args.token,
    contentType: args.mimeType,
    addRandomSuffix: true,
  });

  return { url: result.url, byteCount: args.bytes.byteLength };
};

function defaultRandomKey(): string {
  // Vercel Blob runs addRandomSuffix anyway; this is a readable namespace.
  return Date.now().toString(36);
}
