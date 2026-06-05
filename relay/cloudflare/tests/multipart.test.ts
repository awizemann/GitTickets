import { describe, expect, it } from "vitest";

import { extractFilePart, MultipartError } from "../src/lib/multipart.js";

function buildMultipart(opts: {
  boundary: string;
  filename: string;
  mime: string;
  payload: Uint8Array;
}): Uint8Array {
  const encoder = new TextEncoder();
  const head = encoder.encode(
    `--${opts.boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${opts.filename}"\r\n` +
      `Content-Type: ${opts.mime}\r\n\r\n`,
  );
  const tail = encoder.encode(`\r\n--${opts.boundary}--\r\n`);
  const out = new Uint8Array(head.byteLength + opts.payload.byteLength + tail.byteLength);
  out.set(head, 0);
  out.set(opts.payload, head.byteLength);
  out.set(tail, head.byteLength + opts.payload.byteLength);
  return out;
}

describe("multipart extractFilePart (Workers)", () => {
  const boundary = "gittickets-abc123";

  it("extracts a single file part", () => {
    const payload = new Uint8Array([0x89, 0x50, 0x4e, 0x47]);
    const body = buildMultipart({ boundary, filename: "shot.png", mime: "image/png", payload });
    const part = extractFilePart(body, `multipart/form-data; boundary=${boundary}`);
    expect(part.fieldName).toBe("file");
    expect(part.filename).toBe("shot.png");
    expect(part.mimeType).toBe("image/png");
    expect(Array.from(part.data)).toEqual(Array.from(payload));
  });

  it("preserves binary bytes including embedded CRLF", () => {
    const payload = new Uint8Array([0x00, 0x0d, 0x0a, 0xff, 0x80]);
    const body = buildMultipart({ boundary, filename: "blob.bin", mime: "application/octet-stream", payload });
    const part = extractFilePart(body, `multipart/form-data; boundary=${boundary}`);
    expect(Array.from(part.data)).toEqual(Array.from(payload));
  });

  it("rejects missing boundary", () => {
    expect(() => extractFilePart(new TextEncoder().encode("anything"), "multipart/form-data")).toThrow(
      MultipartError,
    );
  });

  it("rejects when no part is present", () => {
    const body = new TextEncoder().encode(`--${boundary}--\r\n`);
    expect(() =>
      extractFilePart(body, `multipart/form-data; boundary=${boundary}`),
    ).toThrow(MultipartError);
  });
});
