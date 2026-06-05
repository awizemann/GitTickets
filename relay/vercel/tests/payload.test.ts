import { describe, expect, it } from "vitest";

import {
  ReportRequestSchema,
  MyIssuesRequestSchema,
  bodyContainsMarker,
  ALLOWED_MIME_TYPES,
  extensionForMime,
} from "../api/_lib/payload.js";

const validReport = {
  schemaVersion: 1,
  title: "Crash on launch",
  body: "Bug body with the magic marker.\n\n<!-- gittickets-id: AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE -->",
  labels: ["bug", "gittickets"],
  submissionID: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  deviceID: "device-1",
  attachmentURLs: [] as string[],
};

describe("ReportRequestSchema", () => {
  it("accepts a valid payload", () => {
    expect(() => ReportRequestSchema.parse(validReport)).not.toThrow();
  });

  it("rejects wrong schemaVersion", () => {
    expect(() => ReportRequestSchema.parse({ ...validReport, schemaVersion: 99 })).toThrow();
  });

  it("rejects empty title", () => {
    expect(() => ReportRequestSchema.parse({ ...validReport, title: "  " })).toThrow();
  });

  it("rejects malformed submissionID", () => {
    expect(() => ReportRequestSchema.parse({ ...validReport, submissionID: "not-a-uuid" })).toThrow();
  });

  it("rejects too many labels", () => {
    const labels = new Array(21).fill("x");
    expect(() => ReportRequestSchema.parse({ ...validReport, labels })).toThrow();
  });

  it("normalizes submissionID to uppercase", () => {
    const parsed = ReportRequestSchema.parse({
      ...validReport,
      submissionID: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    });
    expect(parsed.submissionID).toBe("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
  });
});

describe("MyIssuesRequestSchema", () => {
  it("accepts a valid payload", () => {
    const parsed = MyIssuesRequestSchema.parse({
      schemaVersion: 1,
      submissionIDs: ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"],
      deviceID: "device-1",
    });
    expect(parsed.submissionIDs).toHaveLength(1);
  });

  it("caps submissionIDs at 200 entries", () => {
    const submissionIDs = new Array(201).fill("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE");
    expect(() =>
      MyIssuesRequestSchema.parse({ schemaVersion: 1, submissionIDs, deviceID: "x" }),
    ).toThrow();
  });
});

describe("bodyContainsMarker", () => {
  it("matches present marker case-insensitively", () => {
    expect(
      bodyContainsMarker(
        "Body\n<!-- gittickets-id: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee -->",
        "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      ),
    ).toBe(true);
  });

  it("rejects when marker mismatches", () => {
    expect(
      bodyContainsMarker(
        "Body\n<!-- gittickets-id: 11111111-2222-3333-4444-555555555555 -->",
        "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      ),
    ).toBe(false);
  });

  it("rejects when marker is absent", () => {
    expect(bodyContainsMarker("Plain body.", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")).toBe(false);
  });
});

describe("MIME whitelist", () => {
  it("includes the SDK-side whitelist", () => {
    for (const m of [
      "image/png",
      "image/jpeg",
      "image/gif",
      "image/webp",
      "image/heic",
      "application/octet-stream",
      "text/plain",
    ]) {
      expect(ALLOWED_MIME_TYPES.has(m)).toBe(true);
    }
  });

  it("maps MIME to extension", () => {
    expect(extensionForMime("image/png")).toBe("png");
    expect(extensionForMime("image/jpeg")).toBe("jpg");
    expect(extensionForMime("application/octet-stream")).toBe("bin");
  });
});
