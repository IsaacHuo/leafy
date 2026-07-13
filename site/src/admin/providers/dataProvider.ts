import type {
  CreateParams,
  DataProvider,
  DeleteManyParams,
  DeleteParams,
  GetListParams,
  GetOneParams,
  RaRecord,
  UpdateManyParams,
  UpdateParams,
} from "react-admin";
import type { ExportRequest, GlobalSearchResult } from "../contracts";
import { actionRequest, exportRequest } from "./client";
import { readCampusScope } from "./session";

type ListResult = { items: RaRecord[]; total: number; page: number; pageSize: number };

const listActions: Record<string, string> = {
  campuses: "listCampuses",
  "campus-requests": "listCampusRequests",
  posts: "listPosts",
  polls: "listPolls",
  comments: "listComments",
  reports: "listModerationReports",
  profiles: "listProfiles",
  feedback: "listFeedback",
  announcements: "listAnnouncements",
  postgraduate: "listPostgraduateSources",
  "postgraduate-suggestions": "listPostgraduateSuggestions",
  suggestions: "listCatalogSuggestions",
  teachers: "listTeachers",
  courses: "listCourses",
  dishes: "listDishes",
  ratings: "listTeacherRatings",
  "semester-configs": "listSemesterRuntimeConfigs",
  "national-calendar": "listNationalCalendarRuntimeConfigs",
  admins: "listAdmins",
  sessions: "listAdminSessions",
  "audit-logs": "listAuditLogs",
};

const getOneActions: Record<string, string> = {
  posts: "getPost",
  polls: "getPoll",
  profiles: "getProfile",
};

const unscopedActions = new Set([
  "listCampuses", "listCampusRequests", "approveCampusRequest", "rejectCampusRequest",
  "listPostgraduateSources", "listPostgraduateSuggestions", "upsertPostgraduateSource",
  "setPostgraduateSourceStatus", "approvePostgraduateSuggestion", "rejectPostgraduateSuggestion",
  "listNationalCalendarRuntimeConfigs", "upsertNationalCalendarRuntimeConfig",
  "listAdmins", "createAdmin", "updateAdmin", "disableAdmin", "listAdminSessions",
  "revokeAdminSession", "listAuditLogs",
]);

export type AdminDataProvider = DataProvider & {
  execute<T = unknown>(action: string, params?: Record<string, unknown>): Promise<T>;
  globalSearch(query: string, resources?: string[]): Promise<GlobalSearchResult[]>;
  download(request: ExportRequest): Promise<void>;
};

const providerImplementation = {
  getList: async (resource: string, params: GetListParams) => {
    let action = requireMapping(listActions, resource);
    const filter = { ...(params.filter ?? {}) } as Record<string, unknown>;
    if (resource === "ratings" && filter.target === "dish") action = "listDishRatings";
    const response = await actionRequest<ListResult>(action, withCampus(action, {
      ...filter,
      page: Math.max(0, (params.pagination?.page ?? 1) - 1),
      pageSize: params.pagination?.perPage ?? 20,
      sortField: params.sort?.field,
      sortOrder: params.sort?.order,
      timezoneOffsetMinutes: new Date().getTimezoneOffset(),
    }));
    return { data: response.data.items, total: response.data.total };
  },
  getOne: async (resource: string, params: GetOneParams) => {
    const action = requireMapping(getOneActions, resource);
    const response = await actionRequest<Record<string, unknown>>(action, withCampus(action, { id: params.id }));
    return { data: ensureID(response.data as RaRecord, params.id) };
  },
  getMany: async () => ({ data: [] }),
  getManyReference: async (resource: string, params: GetListParams) => dataProvider.getList(resource, params),
  create: async (resource: string, params: CreateParams) => {
    const action = createAction(resource);
    const response = await actionRequest<RaRecord>(action, withCampus(action, params.data));
    return { data: ensureID(response.data) };
  },
  update: async (resource: string, params: UpdateParams) => {
    const action = updateAction(resource);
    const response = await actionRequest<RaRecord>(action, withCampus(action, { id: params.id, ...params.data }));
    return { data: ensureID(response.data, params.id) };
  },
  updateMany: async (resource: string, params: UpdateManyParams) => {
    const action = resource === "posts" ? "bulkModeratePosts" : resource === "comments" ? "bulkModerateComments" : null;
    if (!action) throw new Error(`Resource ${resource} does not support bulk update.`);
    await actionRequest(action, withCampus(action, { ids: params.ids, ...params.data }));
    return { data: params.ids };
  },
  delete: async (resource: string, params: DeleteParams) => {
    const action = deleteAction(resource, params.previousData as Record<string, unknown> | undefined);
    const payload = resource === "ratings"
      ? ratingDeletePayload(params.previousData as Record<string, unknown>)
      : { id: params.id };
    const response = await actionRequest<RaRecord>(action, withCampus(action, payload));
    return { data: ensureID(response.data, params.id) };
  },
  deleteMany: async (resource: string, params: DeleteManyParams) => {
    if (resource === "posts" || resource === "comments") {
      return dataProvider.updateMany(resource, { ids: params.ids, data: { status: "hidden", reason: "批量下架" } });
    }
    throw new Error(`Resource ${resource} does not support bulk delete.`);
  },
  execute: async <T,>(action: string, params: Record<string, unknown> = {}) => {
    const response = await actionRequest<T>(action, withCampus(action, params));
    return response.data;
  },
  globalSearch: async (query: string, resources?: string[]) => {
    const response = await actionRequest<GlobalSearchResult[]>("globalSearch", withCampus("globalSearch", { query, resources }));
    return response.data;
  },
  download: async (request: ExportRequest) => {
    const campusID = readCampusScope();
    const { blob, filename } = await exportRequest({
      ...request,
      filters: { ...(request.filters ?? {}), ...(campusID !== "all" ? { campusID } : {}) },
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    anchor.click();
    URL.revokeObjectURL(url);
  },
};

export const dataProvider = providerImplementation as unknown as AdminDataProvider;

function withCampus(action: string, params: Record<string, unknown>) {
  const campusID = readCampusScope();
  return campusID === "all" || unscopedActions.has(action) ? params : { ...params, campusID };
}

function requireMapping(mapping: Record<string, string>, resource: string) {
  const action = mapping[resource];
  if (!action) throw new Error(`Unsupported admin resource: ${resource}`);
  return action;
}

function createAction(resource: string) {
  return requireMapping({
    announcements: "createAnnouncement",
    postgraduate: "upsertPostgraduateSource",
    teachers: "upsertTeacher",
    courses: "upsertCourse",
    dishes: "upsertDish",
    admins: "createAdmin",
    "semester-configs": "upsertSemesterRuntimeConfig",
    "national-calendar": "upsertNationalCalendarRuntimeConfig",
  }, resource);
}

function updateAction(resource: string) {
  return requireMapping({
    announcements: "updateAnnouncement",
    postgraduate: "upsertPostgraduateSource",
    teachers: "upsertTeacher",
    courses: "upsertCourse",
    dishes: "upsertDish",
    admins: "updateAdmin",
    feedback: "updateFeedback",
    "semester-configs": "upsertSemesterRuntimeConfig",
    "national-calendar": "upsertNationalCalendarRuntimeConfig",
  }, resource);
}

function deleteAction(resource: string, record?: Record<string, unknown>) {
  if (resource === "sessions") return "revokeAdminSession";
  if (resource === "admins") return "disableAdmin";
  if (resource === "ratings") return record?.target === "dish" || record?.dish_id ? "deleteDishRating" : "deleteTeacherRating";
  throw new Error(`Resource ${resource} does not support delete.`);
}

function ratingDeletePayload(record: Record<string, unknown>) {
  return record?.dish_id
    ? { dishID: record.dish_id, userID: record.user_id }
    : { teacherID: record.teacher_id, userID: record.user_id };
}

function ensureID<T extends RaRecord>(value: T, fallback?: string | number) {
  return value?.id == null && fallback != null ? { ...value, id: fallback } : value;
}
