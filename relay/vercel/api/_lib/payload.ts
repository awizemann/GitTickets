/**
 * Zod schemas for inbound request bodies. Match Swift's `RelayPayload.swift`
 * exactly — any change here must be paired with a SDK update + schemaVersion
 * bump.
 */

import { z } from "zod";

export const CURRENT_REPORT_SCHEMA_VERSION = 1;
export const CURRENT_MY_ISSUES_SCHEMA_VERSION = 1;
export const CURRENT_COMMENTS_SCHEMA_VERSION = 1;

export const ReportRequestSchema = z.object({
  schemaVersion: z.literal(CURRENT_REPORT_SCHEMA_VERSION),
  title: z.string().trim().min(1).max(256),
  body: z.string().min(1).max(65_536),
  labels: z.array(z.string().min(1).max(50)).max(20),
  submissionID: z
    .string()
    .uuid()
    .transform((s) => s.toUpperCase()),
  deviceID: z.string().min(1).max(128),
  attachmentURLs: z.array(z.string().url()).max(20),
});

export type ReportRequest = z.infer<typeof ReportRequestSchema>;

export const MyIssuesRequestSchema = z.object({
  schemaVersion: z.literal(CURRENT_MY_ISSUES_SCHEMA_VERSION),
  submissionIDs: z
    .array(z.string().uuid().transform((s) => s.toUpperCase()))
    .max(200),
  deviceID: z.string().min(1).max(128),
});

export type MyIssuesRequest = z.infer<typeof MyIssuesRequestSchema>;

export const CommentsRequestSchema = z.object({
  schemaVersion: z.literal(CURRENT_COMMENTS_SCHEMA_VERSION),
  issueNumber: z.number().int().positive(),
  deviceID: z.string().min(1).max(128),
});

export type CommentsRequest = z.infer<typeof CommentsRequestSchema>;

/** Allowed attachment MIME types. Mirrors the Swift-side whitelist in
 *  `RelayClient.validateMimeType` so a request rejected here would also
 *  be rejected client-side. */
export const ALLOWED_MIME_TYPES = new Set([
  "image/png",
  "image/jpeg",
  "image/gif",
  "image/webp",
  "image/heic",
  "application/octet-stream",
  "text/plain",
]);

/** Extension hint for Vercel Blob keys. Falls back to `.bin`. */
export function extensionForMime(mime: string): string {
  const map: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/gif": "gif",
    "image/webp": "webp",
    "image/heic": "heic",
    "text/plain": "txt",
  };
  return map[mime] ?? "bin";
}

/** Body must contain the marker matching `submissionID`. Validates the
 *  client didn't accidentally drop it from the assembled markdown. */
export function bodyContainsMarker(
  body: string,
  submissionID: string,
): boolean {
  const target = submissionID.toUpperCase();
  const match = body.match(/<!--\s*gittickets-id:\s*([0-9a-fA-F-]{36})\s*-->/);
  return match?.[1]?.toUpperCase() === target;
}
