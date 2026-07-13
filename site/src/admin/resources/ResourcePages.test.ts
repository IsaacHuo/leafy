import { describe, expect, it } from "vitest";
import { actionConfirmation } from "./ResourcePages";
import { resourceConfigs } from "./config";

describe("admin action confirmations", () => {
  it("identifies a rating even when the user nickname is blank", () => {
    const action = resourceConfigs.ratings.actions?.[0];
    if (!action) throw new Error("Missing rating delete action");
    const confirmation = actionConfirmation("ratings", {
      id: "teacher:341:user-1",
      teacher_id: 341,
      user_id: "user-1",
      teacher: { name: "测试教师" },
      user: { nickname: "" },
      stars: 4,
      updated_at: "2026-07-13T08:00:00Z",
    }, action);

    expect(confirmation.summary).toContain("评分：测试教师 · 4 星 · 用户：user-1");
    expect(confirmation.summary).not.toContain("undefined");
    expect(confirmation.summary).not.toMatch(/^删除/);
  });
});
