import { describe, expect, it } from "vitest";
import { resourceConfigs } from "./config";

describe("admin resource capabilities", () => {
  it("keeps feedback edit-only", () => {
    expect(resourceConfigs.feedback.createForm).toBeUndefined();
    expect(resourceConfigs.feedback.editForm).toBeDefined();
    expect(resourceConfigs.feedback.statusChoices?.find((choice) => choice.id === "reviewed")?.name).toBe("已查看待处理");
  });

  it("requires a password only when creating an admin", () => {
    expect(resourceConfigs.admins.createForm?.find((field) => field.source === "password")?.required).toBe(true);
    expect(resourceConfigs.admins.editForm?.find((field) => field.source === "password")?.required).not.toBe(true);
  });

  it("uses delete permission for destructive row actions", () => {
    expect(resourceConfigs.ratings.actions?.[0].permissionAction).toBe("delete");
    expect(resourceConfigs.sessions.actions?.[0].permissionAction).toBe("delete");
    expect(resourceConfigs.admins.actions?.[0].permissionAction).toBe("delete");
  });

  it("only marks backend-supported columns sortable", () => {
    expect(resourceConfigs.feedback.columns.find((column) => column.source === "created_at")?.sortable).toBe(true);
    expect(resourceConfigs.feedback.columns.find((column) => column.source === "body")?.sortable).toBe(false);
    expect(resourceConfigs.ratings.defaultSort).toEqual({ field: "updated_at", order: "DESC" });
  });

  it("hides generic search for resources without a search contract", () => {
    for (const resource of ["ratings", "sessions", "audit-logs", "semester-configs", "national-calendar"]) {
      expect(resourceConfigs[resource].searchable).toBe(false);
    }
  });

  it("does not expose moderation actions for terminal deleted records", () => {
    for (const resource of ["posts", "polls", "comments"]) {
      const visible = resourceConfigs[resource].actions?.filter((action) => !action.visible || action.visible({ status: "deleted" })) ?? [];
      expect(visible).toHaveLength(0);
    }
  });

  it("shows approval actions only while suggestions remain open", () => {
    for (const resource of ["suggestions", "postgraduate-suggestions"]) {
      const actions = resourceConfigs[resource].actions ?? [];
      expect(actions.every((action) => action.visible?.({ status: "open" }) === true)).toBe(true);
      expect(actions.every((action) => action.visible?.({ status: "approved" }) === false)).toBe(true);
    }
  });
});
