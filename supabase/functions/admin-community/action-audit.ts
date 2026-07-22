export type AdminActionAuditRow = {
  action: string;
  role: "viewer" | "operator" | "super_admin";
  campusPolicy: "global" | "optional" | "required";
  mutating: boolean;
  transactionBoundary: "read_only" | "single_write" | "transaction_rpc";
  auditTarget: string;
};

export const auditedAdminActionNames = [
  "overview", "listCampuses", "listCampusRequests", "approveCampusRequest", "rejectCampusRequest",
  "listPosts", "previewCommunityFeed", "getPost", "moderatePost", "bulkModeratePosts",
  "listPolls", "getPoll", "moderatePoll", "reviewPollDeletion", "listPostPins", "pinPost", "unpinPost",
  "listComments", "listModerationReports", "resolveModerationReport", "moderateComment", "bulkModerateComments",
  "listProfiles", "getProfile", "muteProfile", "unmuteProfile", "listFeedback", "updateFeedback",
  "listAnnouncements", "createAnnouncement", "updateAnnouncement", "listPostgraduateSources",
  "upsertPostgraduateSource", "setPostgraduateSourceStatus", "listPostgraduateSuggestions",
  "approvePostgraduateSuggestion", "rejectPostgraduateSuggestion", "listCatalogSuggestions",
  "approveCatalogSuggestion", "rejectCatalogSuggestion", "listTeachers", "upsertTeacher", "setTeacherStatus",
  "listCourses", "upsertCourse", "setCourseStatus", "listDishes", "upsertDish", "setDishStatus",
  "listTeacherRatings", "listDishRatings", "deleteTeacherRating", "deleteDishRating",
  "listSemesterRuntimeConfigs", "upsertSemesterRuntimeConfig", "listAdmins", "createAdmin", "updateAdmin",
  "disableAdmin", "listAuditLogs", "globalSearch", "listAdminSessions", "revokeAdminSession",
  "listNationalCalendarRuntimeConfigs", "upsertNationalCalendarRuntimeConfig",
] as const;

const operatorActions = new Set<string>([
  "approveCampusRequest", "rejectCampusRequest", "moderatePost", "bulkModeratePosts", "moderatePoll",
  "reviewPollDeletion", "pinPost", "unpinPost", "resolveModerationReport", "moderateComment",
  "bulkModerateComments", "muteProfile", "unmuteProfile", "updateFeedback", "createAnnouncement",
  "updateAnnouncement", "upsertPostgraduateSource", "setPostgraduateSourceStatus",
  "approvePostgraduateSuggestion", "rejectPostgraduateSuggestion", "approveCatalogSuggestion",
  "rejectCatalogSuggestion", "upsertTeacher", "setTeacherStatus", "upsertCourse", "setCourseStatus",
  "upsertDish", "setDishStatus", "deleteTeacherRating", "deleteDishRating", "upsertSemesterRuntimeConfig",
  "upsertNationalCalendarRuntimeConfig",
]);

const superAdminActions = new Set<string>([
  "listAdmins", "createAdmin", "updateAdmin", "disableAdmin", "listAuditLogs", "listAdminSessions",
  "revokeAdminSession",
]);

const globalActions = new Set<string>([
  "listCampuses", "listCampusRequests", "approveCampusRequest", "rejectCampusRequest",
  "listPostgraduateSources", "upsertPostgraduateSource", "setPostgraduateSourceStatus",
  "listPostgraduateSuggestions", "approvePostgraduateSuggestion", "rejectPostgraduateSuggestion",
  "listAdmins", "createAdmin", "updateAdmin", "disableAdmin", "listAuditLogs", "listAdminSessions",
  "revokeAdminSession", "listNationalCalendarRuntimeConfigs", "upsertNationalCalendarRuntimeConfig",
]);

const requiredCampusActions = new Set<string>(["upsertTeacher", "upsertCourse", "upsertDish"]);
const transactionRPCActions = new Set<string>([
  "approveCampusRequest", "rejectCampusRequest", "moderatePost", "bulkModeratePosts", "pinPost",
  "resolveModerationReport", "approvePostgraduateSuggestion", "approveCatalogSuggestion",
  "upsertSemesterRuntimeConfig", "createAdmin", "updateAdmin", "disableAdmin",
  "upsertNationalCalendarRuntimeConfig",
]);

export const adminActionAuditMatrix: readonly AdminActionAuditRow[] = auditedAdminActionNames.map((action) => {
  const role = superAdminActions.has(action) ? "super_admin" : operatorActions.has(action) ? "operator" : "viewer";
  const mutating = operatorActions.has(action) || ["createAdmin", "updateAdmin", "disableAdmin", "revokeAdminSession"].includes(action);
  return {
    action,
    role,
    campusPolicy: requiredCampusActions.has(action) ? "required" : globalActions.has(action) ? "global" : "optional",
    mutating,
    transactionBoundary: !mutating ? "read_only" : transactionRPCActions.has(action) ? "transaction_rpc" : "single_write",
    auditTarget: auditTargetFor(action),
  };
});

function auditTargetFor(action: string) {
  if (action.includes("CatalogSuggestion")) return "catalog_suggestion";
  if (action.includes("PostgraduateSuggestion")) return "postgraduate_source_suggestion";
  if (action.includes("PostgraduateSource")) return "postgraduate_source";
  if (action.includes("ModerationReport")) return "community_report";
  if (action.includes("Post")) return "post";
  if (action.includes("Poll")) return "poll";
  if (action.includes("Comment")) return "comment";
  if (action.includes("Profile")) return "profile";
  if (action.includes("Teacher")) return "teacher";
  if (action.includes("Course")) return "course";
  if (action.includes("Dish")) return "dish";
  if (action.includes("Admin") || action.includes("Session")) return "admin";
  return action;
}
