/**
 * Minimal multipart/form-data parser for a single `file` part.
 *
 * We deliberately don't use `multer` or `busboy` here — they're built for
 * disk-staged uploads and brought in via Express middleware. The relay
 * receives at most one file per request and the entire body is already
 * buffered (we needed the raw bytes for HMAC anyway), so a 60-line in-house
 * parser is simpler and avoids two dependencies.
 */

import { Buffer } from "node:buffer";

export interface MultipartFile {
  fieldName: string;
  filename: string;
  mimeType: string;
  data: Buffer;
}

const CRLF = Buffer.from("\r\n");
const DOUBLE_CRLF = Buffer.from("\r\n\r\n");

export function extractFilePart(
  body: Buffer,
  contentType: string,
): MultipartFile {
  const boundaryMatch = /boundary=(?:"([^"]+)"|([^;,\s]+))/i.exec(contentType);
  const boundary = boundaryMatch?.[1] ?? boundaryMatch?.[2];
  if (!boundary) {
    throw new MultipartError("Missing boundary in Content-Type.");
  }

  const delimiter = Buffer.from(`--${boundary}`);
  const closingDelimiter = Buffer.from(`--${boundary}--`);

  // Locate the first body part — skip the preamble before the first delimiter.
  let cursor = body.indexOf(delimiter);
  if (cursor === -1) throw new MultipartError("No boundary delimiter found.");
  cursor += delimiter.byteLength;

  // Each part begins with CRLF after the boundary.
  if (body.slice(cursor, cursor + CRLF.byteLength).equals(CRLF)) {
    cursor += CRLF.byteLength;
  } else if (body.slice(cursor - 2, cursor).equals(Buffer.from("--"))) {
    throw new MultipartError("Multipart envelope is empty.");
  }

  // Body part: headers, CRLFCRLF, content, CRLF, next boundary or closing.
  const headerEnd = body.indexOf(DOUBLE_CRLF, cursor);
  if (headerEnd === -1) throw new MultipartError("Malformed part headers.");
  const headerBlock = body.slice(cursor, headerEnd).toString("utf8");
  const headers = parseHeaders(headerBlock);

  const disposition = headers["content-disposition"];
  if (!disposition || !/form-data/i.test(disposition)) {
    throw new MultipartError("First part is not form-data.");
  }
  const nameMatch = /\bname="([^"]+)"/.exec(disposition);
  const filenameMatch = /\bfilename="([^"]*)"/.exec(disposition);
  if (!nameMatch || !filenameMatch) {
    throw new MultipartError("Part is missing name= or filename=.");
  }
  const mimeType = headers["content-type"]?.split(";")[0]?.trim() ?? "application/octet-stream";

  const contentStart = headerEnd + DOUBLE_CRLF.byteLength;
  // Find the next boundary that ends this part.
  const nextDelim = body.indexOf(delimiter, contentStart);
  if (nextDelim === -1) throw new MultipartError("Unterminated part.");
  // The CRLF immediately before the next delimiter belongs to the framing,
  // not the content.
  const contentEnd = body.slice(nextDelim - CRLF.byteLength, nextDelim).equals(CRLF)
    ? nextDelim - CRLF.byteLength
    : nextDelim;
  const data = body.slice(contentStart, contentEnd);

  return {
    fieldName: nameMatch[1] ?? "",
    filename: filenameMatch[1] ?? "",
    mimeType,
    data,
  };
}

function parseHeaders(block: string): Record<string, string> {
  const headers: Record<string, string> = {};
  for (const line of block.split(/\r?\n/)) {
    const idx = line.indexOf(":");
    if (idx === -1) continue;
    const key = line.slice(0, idx).trim().toLowerCase();
    const value = line.slice(idx + 1).trim();
    headers[key] = value;
  }
  return headers;
}

export class MultipartError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MultipartError";
  }
}
