import { describe, expect, it } from "vitest";
import { formatBucketDate } from "./Dashboard";

describe("dashboard daily bucket labels", () => {
  it("formats the backend bucket_date contract", () => {
    expect(formatBucketDate("2026-07-13")).toBe("07-13");
    expect(formatBucketDate("2026-07-13T00:00:00Z")).toBe("07-13");
  });

  it("never exposes malformed values as undefined", () => {
    expect(formatBucketDate("")).toBe("—");
    expect(formatBucketDate("undefined")).toBe("—");
  });
});
