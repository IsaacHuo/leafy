import { describe, expect, it } from "vitest";
import { i18nProvider } from "./AdminConsole";

describe("admin Chinese translations", () => {
  it("prefers the Chinese catalog over React Admin English defaults", () => {
    expect(i18nProvider.translate("ra.navigation.no_results", { _: "No results found" })).toBe("暂无数据");
    expect(i18nProvider.translate("ra.action.refresh", { _: "Refresh" })).toBe("刷新");
  });
});
