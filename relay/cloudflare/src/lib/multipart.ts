/**
 * Worker-native multipart/form-data parser. Pure Uint8Array — no Node Buffer
 * dependency. Matches the contract of the Vercel parser.
 */

export interface MultipartFile {
  fieldName: string;
  filename: string;
  mimeType: string;
  data: Uint8Array;
}

const CRLF = new Uint8Array([0x0d, 0x0a]);
const DOUBLE_CRLF = new Uint8Array([0x0d, 0x0a, 0x0d, 0x0a]);

export function extractFilePart(
  body: Uint8Array,
  contentType: string,
): MultipartFile {
  const boundaryMatch = /boundary=(?:"([^"]+)"|([^;,\s]+))/i.exec(contentType);
  const boundary = boundaryMatch?.[1] ?? boundaryMatch?.[2];
  if (!boundary) {
    throw new MultipartError("Missing boundary in Content-Type.");
  }

  const encoder = new TextEncoder();
  const delimiter = encoder.encode(`--${boundary}`);

  let cursor = indexOf(body, delimiter, 0);
  if (cursor === -1) throw new MultipartError("No boundary delimiter found.");
  cursor += delimiter.byteLength;

  // Skip optional CRLF after the leading boundary.
  if (startsWith(body, CRLF, cursor)) {
    cursor += CRLF.byteLength;
  } else if (cursor + 1 < body.byteLength && body[cursor] === 0x2d && body[cursor + 1] === 0x2d) {
    throw new MultipartError("Multipart envelope is empty.");
  }

  const headerEnd = indexOf(body, DOUBLE_CRLF, cursor);
  if (headerEnd === -1) throw new MultipartError("Malformed part headers.");
  const headerText = new TextDecoder().decode(body.subarray(cursor, headerEnd));
  const headers = parseHeaders(headerText);

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
  const nextDelim = indexOf(body, delimiter, contentStart);
  if (nextDelim === -1) throw new MultipartError("Unterminated part.");

  // CRLF immediately before the next delimiter is part of the framing.
  const trimmedEnd = startsWith(body, CRLF, nextDelim - CRLF.byteLength)
    ? nextDelim - CRLF.byteLength
    : nextDelim;
  const data = body.slice(contentStart, trimmedEnd);

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

function indexOf(haystack: Uint8Array, needle: Uint8Array, start: number): number {
  if (needle.byteLength === 0) return start;
  outer: for (let i = start; i <= haystack.byteLength - needle.byteLength; i += 1) {
    for (let j = 0; j < needle.byteLength; j += 1) {
      if (haystack[i + j] !== needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

function startsWith(haystack: Uint8Array, needle: Uint8Array, at: number): boolean {
  if (at < 0 || at + needle.byteLength > haystack.byteLength) return false;
  for (let j = 0; j < needle.byteLength; j += 1) {
    if (haystack[at + j] !== needle[j]) return false;
  }
  return true;
}

export class MultipartError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MultipartError";
  }
}
