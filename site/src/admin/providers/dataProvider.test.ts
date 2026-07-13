import { beforeEach, describe, expect, it, vi } from "vitest";
import { actionRequest } from "./client";
import { dataProvider } from "./dataProvider";
import { saveCampusScope } from "./session";

vi.mock("./client", () => ({
  actionRequest: vi.fn(),
  exportRequest: vi.fn(),
}));

const mockedAction = vi.mocked(actionRequest);

describe("admin data provider campus scope", () => {
  beforeEach(() => {
    localStorage.clear();
    mockedAction.mockReset();
  });

  it("injects campus scope into campus-owned resources", async () => {
    saveCampusScope("campus-a");
    mockedAction.mockResolvedValue({ data: { items: [{ id: "p1" }], total: 1, page: 0, pageSize: 20 }, meta: {} });
    await dataProvider.getList("posts", { pagination: { page: 1, perPage: 20 }, sort: { field: "created_at", order: "DESC" }, filter: {} });
    expect(mockedAction).toHaveBeenCalledWith("listPosts", expect.objectContaining({ campusID: "campus-a" }));
  });

  it("does not inject campus scope into global resources", async () => {
    saveCampusScope("campus-a");
    mockedAction.mockResolvedValue({ data: { items: [], total: 0, page: 0, pageSize: 20 }, meta: {} });
    await dataProvider.getList("postgraduate", { pagination: { page: 1, perPage: 20 }, sort: { field: "created_at", order: "DESC" }, filter: {} });
    expect(mockedAction).toHaveBeenCalledWith("listPostgraduateSources", expect.not.objectContaining({ campusID: expect.anything() }));
  });

  it("scopes global search to the selected campus", async () => {
    saveCampusScope("campus-a");
    mockedAction.mockResolvedValue({ data: [], meta: {} });
    await dataProvider.globalSearch("测试");
    expect(mockedAction).toHaveBeenCalledWith("globalSearch", { query: "测试", resources: undefined, campusID: "campus-a" });
  });

  it("preserves numeric rating identifiers when deleting", async () => {
    mockedAction.mockResolvedValue({ data: { id: "teacher:341:user-1", teacher_id: 341, user_id: "user-1" }, meta: {} });
    await dataProvider.delete("ratings", {
      id: "teacher:341:user-1",
      previousData: { id: "teacher:341:user-1", target: "teacher", teacher_id: 341, user_id: "user-1" },
    });
    expect(mockedAction).toHaveBeenCalledWith("deleteTeacherRating", { teacherID: 341, userID: "user-1" });
  });

  it("passes date-only filter boundaries without converting them in the browser", async () => {
    mockedAction.mockResolvedValue({ data: { items: [], total: 0, page: 0, pageSize: 20 }, meta: {} });
    await dataProvider.getList("feedback", {
      pagination: { page: 1, perPage: 20 },
      sort: { field: "created_at", order: "DESC" },
      filter: { start: "2026-07-01", end: "2026-07-13" },
    });
    expect(mockedAction).toHaveBeenCalledWith("listFeedback", expect.objectContaining({ start: "2026-07-01", end: "2026-07-13" }));
  });
});
