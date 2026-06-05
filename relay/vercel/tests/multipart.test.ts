import { describe, expect, it } from "vitest";

import { extractFilePart, MultipartError } from "../api/_lib/multipart.js";

function buildMultipart(opts: {
  boundary: string;
  filename: string;
  mime: string;
  payload: Buffer;
}): Buffer {
  const { boundary, filename, mime, payload } = opts;
  const head = Buffer.from(
    `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
      `Content-Type: ${mime}\r\n\r\n`,
    "utf8",
  );
  const tail = Buffer.from(`\r\n--${boundary}--\r\n`, "utf8");
  return Buffer.concat([head, payload, tail]);
}

describe("multipart extractFilePart", () => {
  const boundary = "gittickets-abc123";

  it("extracts a single file part", () => {
    const payload = Buffer.from([0x89, 0x50, 0x4e, 0x47]);
    const body = buildMultipart({ boundary, filename: "shot.png", mime: "image/png", payload });
    const part = extractFilePart(body, `multipart/form-data; boundary=${boundary}`);
    expect(part.fieldName).toBe("file");
    expect(part.filename).toBe("shot.png");
    expect(part.mimeType).toBe("image/png");
    expect(part.data.equals(payload)).toBe(true);
  });

  it("preserves binary bytes including embedded CRLF", () => {
    const payload = Buffer.from([0x00, 0x0d, 0x0a, 0xff, 0x80]);
    const body = buildMultipart({ boundary, filename: "blob.bin", mime: "application/octet-stream", payload });
    const part = extractFilePart(body, `multipart/form-data; boundary=${boundary}`);
    expect(part.data.equals(payload)).toBe(true);
  });

  it("rejects missing boundary", () => {
    expect(() => extractFilePart(Buffer.from("anything"), "multipart/form-data")).toThrow(
      MultipartError,
    );
  });

  it("rejects when no part is present", () => {
    const body = Buffer.from(`--${boundary}--\r\n`, "utf8");
    expect(() =>
      extractFilePart(body, `multipart/form-data; boundary=${boundary}`),
    ).toThrow(MultipartError);
  });

  it("rejects when headers are not terminated", () => {
    const body = Buffer.from(
      `--${boundary}\r\nContent-Disposition: form-data; name="file"; filename="x"\r\nincomplete`,
      "utf8",
    );
    expect(() =>
      extractFilePart(body, `multipart/form-data; boundary=${boundary}`),
    ).toThrow(MultipartError);
  });
});
