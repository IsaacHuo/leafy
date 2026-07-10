import { describe, expectTypeOf, it } from "vitest";
import type {
  ApiMetadata,
  ApiResponse,
  ExportFormat,
  GlobalSearchResponse,
  GlobalSearchResult
} from "./contracts";

describe("shared admin contracts", () => {
  it("uses the standard API metadata fields", () => {
    expectTypeOf<ApiMetadata>().toEqualTypeOf<{
      request_id?: string;
      audit_logged?: boolean;
      duration_ms?: number;
    }>();
  });

  it("wraps global search results in the standard API envelope", () => {
    expectTypeOf<GlobalSearchResponse>().toEqualTypeOf<
      ApiResponse<readonly GlobalSearchResult[]>
    >();
  });

  it("only permits CSV exports", () => {
    expectTypeOf<ExportFormat>().toEqualTypeOf<"csv">();
  });
});
