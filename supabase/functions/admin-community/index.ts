import {
  AdminContext,
  appendAuditLog,
  authenticateAdmin,
  HttpError,
  json,
  mapFunctionError,
  normalizeDate,
  normalizeText,
  readJSON,
  requireOperator,
  requirePost,
  requireSuperAdmin,
} from "../_shared/admin-core.ts";

type ActionRequest = {
  action?: string | null;
  params?: Record<string, unknown> | null;
};

const postgraduateSourceKinds = [
  "admission_notice",
  "major_catalog",
  "score_line",
  "enrollment_plan",
  "bibliography",
  "retest",
  "registration",
  "other",
];

const postgraduateTrustLevels = ["official", "curated", "verified_user"];

const mutatingActions = new Set([
  "moderatePost",
  "bulkModeratePosts",
  "moderatePoll",
  "reviewPollDeletion",
  "pinPost",
  "unpinPost",
  "moderateComment",
  "bulkModerateComments",
  "muteProfile",
  "unmuteProfile",
  "resolveModerationReport",
  "updateFeedback",
  "createAnnouncement",
  "updateAnnouncement",
  "upsertPostgraduateSource",
  "setPostgraduateSourceStatus",
  "approvePostgraduateSuggestion",
  "rejectPostgraduateSuggestion",
  "approveCatalogSuggestion",
  "rejectCatalogSuggestion",
  "upsertTeacher",
  "setTeacherStatus",
  "upsertCourse",
  "setCourseStatus",
  "upsertDish",
  "setDishStatus",
  "approveCampusRequest",
  "rejectCampusRequest",
  "deleteTeacherRating",
  "deleteDishRating",
  "upsertSemesterRuntimeConfig",
  "createAdmin",
  "updateAdmin",
  "disableAdmin",
]);

const superAdminActions = new Set([
  "listAdmins",
  "createAdmin",
  "updateAdmin",
  "disableAdmin",
  "listAuditLogs",
]);

Deno.serve(async (request) => {
  const methodResponse = requirePost(request);
  if (methodResponse) {
    return methodResponse;
  }

  try {
    const context = await authenticateAdmin(request);
    if (context instanceof Response) {
      return context;
    }

    const body = await readJSON<ActionRequest>(request);
    const action = normalizeText(body.action);
    const params = body.params ?? {};

    if (!action) {
      return json({ error: "Missing admin action." }, 400);
    }

    if (mutatingActions.has(action)) {
      requireOperator(context);
    }

    if (superAdminActions.has(action)) {
      requireSuperAdmin(context);
    }

    const data = await handleAction(context, action, params);
    await appendAuditLog(context, action, params, inferTarget(action, params));

    return json({ data });
  } catch (error) {
    return mapFunctionError(error);
  }
});

async function handleAction(context: AdminContext, action: string, params: Record<string, unknown>) {
  switch (action) {
    case "overview":
      return overview(context, params);
    case "listCampuses":
      return listCampuses(context, params);
    case "listCampusRequests":
      return listCampusRequests(context, params);
    case "approveCampusRequest":
      return approveCampusRequest(context, params);
    case "rejectCampusRequest":
      return rejectCampusRequest(context, params);
    case "listPosts":
      return listPosts(context, params);
    case "previewCommunityFeed":
      return previewCommunityFeed(context, params);
    case "getPost":
      return getPost(context, params);
    case "moderatePost":
      return moderatePost(context, params);
    case "bulkModeratePosts":
      return bulkModeratePosts(context, params);
    case "listPolls":
      return listPolls(context, params);
    case "getPoll":
      return getPoll(context, params);
    case "moderatePoll":
      return moderatePoll(context, params);
    case "reviewPollDeletion":
      return reviewPollDeletion(context, params);
    case "listPostPins":
      return listPostPins(context, params);
    case "pinPost":
      return pinPost(context, params);
    case "unpinPost":
      return unpinPost(context, params);
    case "listComments":
      return listComments(context, params);
    case "listModerationReports":
      return listModerationReports(context, params);
    case "resolveModerationReport":
      return resolveModerationReport(context, params);
    case "moderateComment":
      return moderateComment(context, params);
    case "bulkModerateComments":
      return bulkModerateComments(context, params);
    case "listProfiles":
      return listProfiles(context, params);
    case "getProfile":
      return getProfile(context, params);
    case "muteProfile":
      return muteProfile(context, params);
    case "unmuteProfile":
      return unmuteProfile(context, params);
    case "listFeedback":
      return listFeedback(context, params);
    case "updateFeedback":
      return updateFeedback(context, params);
    case "listAnnouncements":
      return listAnnouncements(context, params);
    case "createAnnouncement":
      return createAnnouncement(context, params);
    case "updateAnnouncement":
      return updateAnnouncement(context, params);
    case "listPostgraduateSources":
      return listPostgraduateSources(context, params);
    case "upsertPostgraduateSource":
      return upsertPostgraduateSource(context, params);
    case "setPostgraduateSourceStatus":
      return setPostgraduateSourceStatus(context, params);
    case "listPostgraduateSuggestions":
      return listPostgraduateSuggestions(context, params);
    case "approvePostgraduateSuggestion":
      return approvePostgraduateSuggestion(context, params);
    case "rejectPostgraduateSuggestion":
      return rejectPostgraduateSuggestion(context, params);
    case "listCatalogSuggestions":
      return listCatalogSuggestions(context, params);
    case "approveCatalogSuggestion":
      return approveCatalogSuggestion(context, params);
    case "rejectCatalogSuggestion":
      return rejectCatalogSuggestion(context, params);
    case "listTeachers":
      return listTeachers(context, params);
    case "upsertTeacher":
      return upsertTeacher(context, params);
    case "setTeacherStatus":
      return setTeacherStatus(context, params);
    case "listCourses":
      return listCourses(context, params);
    case "upsertCourse":
      return upsertCourse(context, params);
    case "setCourseStatus":
      return setCourseStatus(context, params);
    case "listDishes":
      return listDishes(context, params);
    case "upsertDish":
      return upsertDish(context, params);
    case "setDishStatus":
      return setDishStatus(context, params);
    case "listTeacherRatings":
      return listTeacherRatings(context, params);
    case "listDishRatings":
      return listDishRatings(context, params);
    case "deleteTeacherRating":
      return deleteTeacherRating(context, params);
    case "deleteDishRating":
      return deleteDishRating(context, params);
    case "listSemesterRuntimeConfigs":
      return listSemesterRuntimeConfigs(context, params);
    case "upsertSemesterRuntimeConfig":
      return upsertSemesterRuntimeConfig(context, params);
    case "listAdmins":
      return listAdmins(context, params);
    case "createAdmin":
      return createAdmin(context, params);
    case "updateAdmin":
      return updateAdmin(context, params);
    case "disableAdmin":
      return disableAdmin(context, params);
    case "listAuditLogs":
      return listAuditLogs(context, params);
    default:
      throw new HttpError(400, `Unknown admin action: ${action}`);
  }
}

async function overview(context: AdminContext, params: Record<string, unknown>) {
  const client = context.adminClient;
  const today = startOfTodayISO();
  const now = new Date().toISOString();
  const days = analyticsDays(params);
  const timezone = analyticsTimezone(params);
  const campusID = scopedCampusID(params);
  const countScopedRows = (
    table: string,
    column: string,
    configure?: (query: any) => any,
  ) => countRows(client, table, (query) => {
    let scopedQuery = campusID ? query.eq(column, campusID) : query;
    if (configure) {
      scopedQuery = configure(scopedQuery);
    }
    return scopedQuery;
  });
  const campusPostIDs = campusID ? await idsForColumn(client, "posts", "campus_id", campusID) : null;
  const countScopedComments = (configure?: (query: any) => any) => {
    if (!campusID) return countRows(client, "comments", configure);
    return countRowsForIDs(client, "comments", "post_id", campusPostIDs ?? [], configure);
  };

  const [
    profileTotal,
    profileNew,
    profileComplete,
    profileMuted,
    postTotal,
    postToday,
    postPublished,
    postHidden,
    postPendingReview,
    commentTotal,
    commentToday,
    commentPublished,
    commentHidden,
    reportOpen,
    reportOverdue,
    feedbackOpen,
    feedbackReviewed,
    feedbackClosed,
    announcementPublished,
    announcementDraft,
    announcementArchived,
    teacherTotal,
    teacherHidden,
    analytics,
  ] = await Promise.all([
    countScopedRows("profiles", "community_campus_id"),
    countScopedRows("profiles", "community_campus_id", (query) => query.gte("created_at", today)),
    countScopedRows("profiles", "community_campus_id", (query) => query.eq("is_profile_complete", true)),
    countScopedRows("profiles", "community_campus_id", (query) => query.gt("muted_until", now)),
    countScopedRows("posts", "campus_id"),
    countScopedRows("posts", "campus_id", (query) => query.gte("created_at", today)),
    countScopedRows("posts", "campus_id", (query) => query.eq("status", "published")),
    countScopedRows("posts", "campus_id", (query) => query.eq("status", "hidden")),
    countScopedRows("posts", "campus_id", (query) => query.eq("status", "pending_review")),
    countScopedComments(),
    countScopedComments((query) => query.gte("created_at", today)),
    countScopedComments((query) => query.eq("status", "published")),
    countScopedComments((query) => query.eq("status", "hidden")),
    countModerationReports(context, campusID, (query) => query.eq("status", "open")),
    countModerationReports(context, campusID, (query) => query.eq("status", "open").lt("created_at", new Date(Date.now() - 24 * 36e5).toISOString())),
    countScopedRows("feedback_submissions", "campus_id", (query) => query.eq("status", "open")),
    countScopedRows("feedback_submissions", "campus_id", (query) => query.eq("status", "reviewed")),
    countScopedRows("feedback_submissions", "campus_id", (query) => query.eq("status", "closed")),
    countScopedRows("site_announcements", "campus_id", (query) => query.eq("status", "published")),
    countScopedRows("site_announcements", "campus_id", (query) => query.eq("status", "draft")),
    countScopedRows("site_announcements", "campus_id", (query) => query.eq("status", "archived")),
    countScopedRows("teachers", "campus_id"),
    countScopedRows("teachers", "campus_id", (query) => query.eq("status", "hidden")),
    buildAnalytics(context, days, timezone, campusID),
  ]);

  let recentFeedbackQuery: any = client
    .from("feedback_submissions")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(6);
  if (campusID) {
    recentFeedbackQuery = recentFeedbackQuery.eq("campus_id", campusID);
  }

  const { data: recentFeedback, error: feedbackError } = await recentFeedbackQuery;

  if (feedbackError) {
    throw new HttpError(500, feedbackError.message);
  }

  const recentPosts = await listPosts(context, { page: 0, pageSize: 6, status: "all", campusID: campusID ?? "all" });
  const summary = buildOverviewSummary({
    days,
    profileTotal,
    profileNew,
    profileComplete,
    profileMuted,
    postTotal,
    postToday,
    postPublished,
    postHidden,
    postPendingReview,
    commentTotal,
    commentToday,
    commentPublished,
    commentHidden,
    reportOpen,
    reportOverdue,
    feedbackOpen,
    feedbackReviewed,
    feedbackClosed,
    teacherTotal,
    teacherHidden,
    analytics,
  });

  return {
    summary,
    cards: {
      profiles: { total: profileTotal, today: profileNew, complete: profileComplete, muted: profileMuted },
      posts: { total: postTotal, today: postToday, published: postPublished, hidden: postHidden, pendingReview: postPendingReview },
      comments: { total: commentTotal, today: commentToday, published: commentPublished, hidden: commentHidden },
      reports: { open: reportOpen, overdue: reportOverdue },
      feedback: { open: feedbackOpen, reviewed: feedbackReviewed, closed: feedbackClosed },
      announcements: { published: announcementPublished, draft: announcementDraft, archived: announcementArchived },
      teachers: { total: teacherTotal, hidden: teacherHidden },
    },
    analytics,
    analyticsMeta: { days, timezone },
    recentFeedback: recentFeedback ?? [],
    recentPosts: recentPosts.items,
  };
}

function buildOverviewSummary(input: {
  days: number;
  profileTotal: number;
  profileNew: number;
  profileComplete: number;
  profileMuted: number;
  postTotal: number;
  postToday: number;
  postPublished: number;
  postHidden: number;
  postPendingReview: number;
  commentTotal: number;
  commentToday: number;
  commentPublished: number;
  commentHidden: number;
  reportOpen: number;
  reportOverdue: number;
  feedbackOpen: number;
  feedbackReviewed: number;
  feedbackClosed: number;
  teacherTotal: number;
  teacherHidden: number;
  analytics: any;
}) {
  const daily = Array.isArray(input.analytics?.daily) ? input.analytics.daily : [];
  const moderation = input.analytics?.moderation ?? {};
  const feedbackAging = Array.isArray(input.analytics?.feedbackAging) ? input.analytics.feedbackAging : [];
  const topPosts = Array.isArray(input.analytics?.topPosts) ? input.analytics.topPosts : [];
  const teacherRatings = input.analytics?.teacherRatings ?? {};
  const topPost = topPosts[0] ?? null;

  return {
    operations: {
      totalProfiles: input.profileTotal,
      activeProfiles: input.profileComplete,
      newProfilesToday: input.profileNew,
      mutedProfiles: input.profileMuted,
      postsToday: input.postToday,
      commentsToday: input.commentToday,
      postsInRange: sumMetric(daily, "posts"),
      commentsInRange: sumMetric(daily, "comments"),
      profilesInRange: sumMetric(daily, "profiles"),
      daily,
    },
    moderation: {
      openReports: input.reportOpen,
      overdueReports: input.reportOverdue,
      hiddenPosts: moderation.hiddenPosts ?? input.postHidden,
      hiddenComments: moderation.hiddenComments ?? input.commentHidden,
      mutedProfiles: moderation.mutedProfiles ?? input.profileMuted,
      pendingPosts: input.postPendingReview,
      publishedPosts: input.postPublished,
      publishedComments: input.commentPublished,
      recentRiskActions: moderation.recentRiskActions ?? [],
    },
    feedback: {
      open: input.feedbackOpen,
      reviewed: input.feedbackReviewed,
      closed: input.feedbackClosed,
      closedInRange: moderation.closedFeedback ?? 0,
      overdue: overdueFeedbackCount(feedbackAging),
      aging: feedbackAging,
    },
    content: {
      topPosts,
      topPostCount: topPosts.length,
      leadingScore: Number(topPost?.score) || 0,
      postsTotal: input.postTotal,
      commentsTotal: input.commentTotal,
    },
    teachers: {
      total: input.teacherTotal,
      hidden: input.teacherHidden,
      ratedTeachers: teacherRatings.teacherCount ?? 0,
      totalRatings: teacherRatings.totalRatings ?? 0,
      average: teacherRatings.average ?? 0,
      stars: teacherRatings.stars ?? [],
      lowScoreTeachers: teacherRatings.lowScoreTeachers ?? [],
    },
    meta: {
      days: input.days,
    },
  };
}

function sumMetric(rows: any[], key: string) {
  return rows.reduce((sum, row) => sum + (Number(row?.[key]) || 0), 0);
}

function overdueFeedbackCount(rows: any[]) {
  return rows.reduce((sum, row) => {
    const key = String(row?.key ?? "");
    return key === "3-7d" || key === "7d+" ? sum + (Number(row?.count) || 0) : sum;
  }, 0);
}

async function buildAnalytics(context: AdminContext, days: number, timezone: string, campusID: string | null) {
  const client = context.adminClient;

  const [
    daily,
    heatmap,
    categories,
    topPosts,
    feedbackAging,
    teacherRatings,
    lowScoreTeachers,
    moderation,
  ] = await Promise.all([
    callRPC(client, "admin_daily_counts", { p_days: days, p_timezone: timezone, p_campus_id: campusID }),
    callRPC(client, "admin_activity_heatmap", { p_days: days, p_timezone: timezone, p_campus_id: campusID }),
    callRPC(client, "admin_category_mix", { p_days: days, p_timezone: timezone, p_campus_id: campusID }),
    callRPC(client, "admin_top_content", { p_days: days, p_timezone: timezone, p_limit: 8, p_campus_id: campusID }),
    feedbackAgingAnalytics(context, campusID),
    teacherRatingAnalytics(context, campusID),
    lowScoreTeacherAnalytics(context, campusID),
    moderationAnalytics(context, days, campusID),
  ]);

  return {
    daily,
    heatmap,
    categories,
    topPosts,
    feedbackAging,
    teacherRatings: {
      ...teacherRatings,
      lowScoreTeachers,
    },
    moderation,
  };
}

async function callRPC(client: any, functionName: string, params: Record<string, unknown>) {
  const { data, error } = await client.rpc(functionName, params);
  if (error) {
    throw new HttpError(500, error.message);
  }
  return data ?? [];
}

async function feedbackAgingAnalytics(context: AdminContext, campusID: string | null) {
  const now = Date.now();
  let query: any = context.adminClient
    .from("feedback_submissions")
    .select("id, status, created_at")
    .in("status", ["open", "reviewed"]);
  if (campusID) {
    query = query.eq("campus_id", campusID);
  }

  const { data, error } = await query;

  if (error) {
    throw new HttpError(500, error.message);
  }

  const buckets = [
    { key: "0-24h", label: "24 小时内", count: 0 },
    { key: "1-3d", label: "1-3 天", count: 0 },
    { key: "3-7d", label: "3-7 天", count: 0 },
    { key: "7d+", label: "7 天以上", count: 0 },
  ];

  for (const item of data ?? []) {
    const ageHours = Math.max(0, (now - new Date(item.created_at).getTime()) / 36e5);
    if (ageHours <= 24) buckets[0].count += 1;
    else if (ageHours <= 72) buckets[1].count += 1;
    else if (ageHours <= 168) buckets[2].count += 1;
    else buckets[3].count += 1;
  }

  return buckets;
}

async function teacherRatingAnalytics(context: AdminContext, campusID: string | null) {
  let query: any = context.adminClient
    .from("teachers")
    .select("rating_average, rating_count, rating_1_count, rating_2_count, rating_3_count, rating_4_count, rating_5_count")
    .gt("rating_count", 0);
  if (campusID) {
    query = query.eq("campus_id", campusID);
  }

  const { data, error } = await query;

  if (error) {
    throw new HttpError(500, error.message);
  }

  const stars = [1, 2, 3, 4, 5].map((star) => ({
    star,
    count: (data ?? []).reduce((sum: number, teacher: any) => sum + (Number(teacher[`rating_${star}_count`]) || 0), 0),
  }));
  const totalRatings = stars.reduce((sum, item) => sum + item.count, 0);
  const weighted = stars.reduce((sum, item) => sum + item.star * item.count, 0);

  return {
    teacherCount: data?.length ?? 0,
    totalRatings,
    average: totalRatings > 0 ? Number((weighted / totalRatings).toFixed(1)) : 0,
    stars,
  };
}

async function lowScoreTeacherAnalytics(context: AdminContext, campusID: string | null) {
  let query: any = context.adminClient
    .from("teachers")
    .select("id, name, unit, status, rating_average, rating_count")
    .eq("status", "published")
    .gt("rating_count", 0)
    .order("rating_average", { ascending: true })
    .order("rating_count", { ascending: false })
    .limit(6);
  if (campusID) {
    query = query.eq("campus_id", campusID);
  }

  const { data, error } = await query;

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data ?? [];
}

async function moderationAnalytics(context: AdminContext, days: number, campusID: string | null) {
  const since = new Date(Date.now() - (days - 1) * 864e5).toISOString();
  const campusPostIDs = campusID ? await idsForColumn(context.adminClient, "posts", "campus_id", campusID) : null;
  const [
    hiddenPosts,
    hiddenComments,
    mutedProfiles,
    openReports,
    overdueReports,
    closedFeedback,
    recentRiskActions,
  ] = await Promise.all([
    countRows(context.adminClient, "posts", (query) => {
      let scopedQuery = campusID ? query.eq("campus_id", campusID) : query;
      return scopedQuery.eq("status", "hidden").gte("moderated_at", since);
    }),
    campusID
      ? countRowsForIDs(context.adminClient, "comments", "post_id", campusPostIDs ?? [], (query) => query.eq("status", "hidden").gte("moderated_at", since))
      : countRows(context.adminClient, "comments", (query) => query.eq("status", "hidden").gte("moderated_at", since)),
    countRows(context.adminClient, "profiles", (query) => {
      let scopedQuery = campusID ? query.eq("community_campus_id", campusID) : query;
      return scopedQuery.gte("muted_at", since);
    }),
    countModerationReports(context, campusID, (query) => query.eq("status", "open")),
    countModerationReports(context, campusID, (query) => query.eq("status", "open").lt("created_at", new Date(Date.now() - 24 * 36e5).toISOString())),
    countRows(context.adminClient, "feedback_submissions", (query) => {
      let scopedQuery = campusID ? query.eq("campus_id", campusID) : query;
      return scopedQuery.eq("status", "closed").gte("reviewed_at", since);
    }),
    context.admin.role === "super_admin" ? recentModerationLogs(context, since) : Promise.resolve([]),
  ]);

  return {
    hiddenPosts,
    hiddenComments,
    mutedProfiles,
    openReports,
    overdueReports,
    closedFeedback,
    recentRiskActions,
  };
}

async function recentModerationLogs(context: AdminContext, since: string) {
  const riskActions = [
    "moderatePost",
    "bulkModeratePosts",
    "pinPost",
    "unpinPost",
    "moderatePoll",
    "reviewPollDeletion",
    "moderateComment",
    "bulkModerateComments",
    "muteProfile",
    "unmuteProfile",
    "resolveModerationReport",
    "deleteTeacherRating",
    "deleteDishRating",
    "disableAdmin",
  ];
  const { data, error } = await context.adminClient
    .from("admin_audit_logs")
    .select("id, admin_id, action, target_type, target_id, created_at")
    .in("action", riskActions)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(8);

  if (error) {
    throw new HttpError(500, error.message);
  }

  const adminMap = await fetchAdminMap(context.adminClient, (data ?? []).map((item: any) => item.admin_id).filter(Boolean));
  return (data ?? []).map((item: any) => ({
    ...item,
    admin: adminMap.get(item.admin_id) ?? null,
  }));
}

async function listCampuses(context: AdminContext, params: Record<string, unknown>) {
  let query: any = context.adminClient
    .from("campuses")
    .select("*")
    .order("is_system", { ascending: false })
    .order("display_name", { ascending: true });

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const { data, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return { items: data ?? [], total: data?.length ?? 0 };
}

async function listCampusRequests(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("campus_membership_requests")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status") ?? "pending";
  if (status !== "all") {
    query = query.eq("status", status);
  }

  const campusID = scopedCampusID(params);
  if (campusID) {
    query = query.or("approved_campus_id.eq." + campusID + ",requested_campus_id.eq." + campusID);
  }

  const search = textParam(params, "search");
  if (search) {
    const safe = likeText(search);
    query = query.or(`school_name.ilike.%${safe}%,admin_note.ilike.%${safe}%`);
  }

  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  const profiles = await fetchProfileMap(context.adminClient, (data ?? []).map((item: any) => item.requester_profile_id));
  return {
    items: (data ?? []).map((item: any) => ({
      ...item,
      requester: profiles.get(item.requester_profile_id) ?? null,
    })),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function approveCampusRequest(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const note = normalizeText(params.note ?? params.adminNote ?? params.admin_note);

  const { data: request, error: requestError } = await context.adminClient
    .from("campus_membership_requests")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (requestError) {
    throw new HttpError(500, requestError.message);
  }
  if (!request) {
    throw new HttpError(404, "Campus request not found.");
  }

  const campusID = await resolveCampusIDForApproval(context, params, request);
  const { data, error } = await context.adminClient.rpc("approve_campus_membership_request", {
    p_request_id: id,
    p_campus_id: campusID,
    p_admin_id: context.admin.id,
    p_admin_note: note,
  });

  if (error) {
    throw new HttpError(500, error.message);
  }

  return Array.isArray(data) ? data[0] : data;
}

async function rejectCampusRequest(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const note = normalizeText(params.note ?? params.adminNote ?? params.admin_note) ?? "学校申请未通过。";

  const { data, error } = await context.adminClient.rpc("reject_campus_membership_request", {
    p_request_id: id,
    p_admin_id: context.admin.id,
    p_admin_note: note,
  });

  if (error) {
    throw new HttpError(500, error.message);
  }

  return Array.isArray(data) ? data[0] : data;
}

async function resolveCampusIDForApproval(context: AdminContext, params: Record<string, unknown>, request: any) {
  if (request.request_type === "school_change") {
    const requestedCampusID = normalizeText(request.requested_campus_id);
    if (!requestedCampusID) {
      throw new HttpError(400, "学校更换申请缺少目标学校。");
    }
    return requestedCampusID;
  }

  const explicitCampusID = normalizeText(params.campusID ?? params.campus_id);
  if (explicitCampusID && explicitCampusID !== "new") {
    if (isBJFUCampusReference(explicitCampusID)) {
      throw new HttpError(400, "北京林业大学用户请使用北林专属入口，通用入口申请不能关联到 bjfu。");
    }
    const { data, error } = await context.adminClient
      .from("campuses")
      .select("id")
      .eq("id", explicitCampusID.toLowerCase())
      .maybeSingle();
    if (error) throw new HttpError(500, error.message);
    if (!data) throw new HttpError(404, "Campus not found.");
    return data.id;
  }

  const displayName = normalizeText(params.displayName ?? params.display_name) ?? request.school_name;
  const normalizedName = normalizeSchoolName(displayName);
  if (isBJFUCampusReference(displayName) || isBJFUCampusReference(normalizedName)) {
    throw new HttpError(400, "北京林业大学用户请使用北林专属入口，通用入口申请不能批准为北林社区身份。");
  }
  const { data: existing, error: existingError } = await context.adminClient
    .from("campuses")
    .select("id")
    .eq("normalized_name", normalizedName)
    .maybeSingle();

  if (existingError) {
    throw new HttpError(500, existingError.message);
  }
  if (existing) {
    if (existing.id === "bjfu") {
      throw new HttpError(400, "北京林业大学用户请使用北林专属入口，通用入口申请不能关联到 bjfu。");
    }
    return existing.id;
  }

  const campusID = normalizeText(params.newCampusID ?? params.new_campus_id)
    ?? campusIDFromRequest(request.id, displayName);
  if (isBJFUCampusReference(campusID)) {
    throw new HttpError(400, "北京林业大学用户请使用北林专属入口，通用入口申请不能创建为 bjfu。");
  }
  const shortName = normalizeText(params.shortName ?? params.short_name) ?? displayName.slice(0, 6);
  const { data: campus, error: campusError } = await context.adminClient
    .from("campuses")
    .insert({
      id: campusID,
      display_name: displayName,
      short_name: shortName,
      connector_kind: "custom",
      status: "active",
      normalized_name: normalizedName,
      is_community_enabled: true,
      is_system: false,
    })
    .select("id")
    .single();

  if (campusError) {
    throw new HttpError(500, campusError.message);
  }
  return campus.id;
}

async function listPosts(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("posts")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const authorID = textParam(params, "authorID");
  if (authorID) {
    query = query.eq("author_id", authorID);
  }

  const category = textParam(params, "category");
  if (category) {
    query = query.ilike("category", `%${likeText(category)}%`);
  }

  const search = textParam(params, "search");
  if (search) {
    const safe = likeText(search);
    query = query.or(`title.ilike.%${safe}%,body.ilike.%${safe}%,category.ilike.%${safe}%`);
  }

  query = applyCampusIDFilter(query, params);
  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    items: await hydratePosts(context, data ?? []),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function previewCommunityFeed(context: AdminContext, params: Record<string, unknown>) {
  const category = textParam(params, "category");
  const search = textParam(params, "search");
  const limit = clamp(numberParam(params, "limit") ?? 20, 1, 50);
  const campusID = scopedCampusID(params) ?? "bjfu";
  const generatedAt = new Date().toISOString();

  const { data, error } = await context.adminClient.rpc("community_feed_v1", {
    p_category: category,
    p_campus_id: campusID,
    p_search: search,
    p_limit: limit,
  });

  if (error) {
    throw new HttpError(500, error.message);
  }

  const posts = Array.isArray(data?.posts) ? data.posts : [];
  return {
    generated_at: data?.generated_at ?? generatedAt,
    source: "community_feed_v1",
    query: { category, campusID, search, limit },
    total: posts.length,
    posts,
  };
}

async function getPost(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const { data, error } = await context.adminClient
    .from("posts")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  if (!data) {
    throw new HttpError(404, "Post not found.");
  }

  const post = (await hydratePosts(context, [data], true))[0];
  const comments = await listComments(context, { postID: id, status: "all", pageSize: 100 });
  return { post, comments: comments.items };
}

async function moderatePost(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["published", "hidden"]);
  const reason = normalizeText(params.reason);

  const { data: current, error: currentError } = await context.adminClient
    .from("posts")
    .select("id, status")
    .eq("id", id)
    .maybeSingle();

  if (currentError) {
    throw new HttpError(500, currentError.message);
  }
  if (!current) {
    throw new HttpError(404, "Post not found.");
  }
  if (current.status === "deleted" && status === "published") {
    throw new HttpError(400, "Cannot restore a post deleted by its author.");
  }

  const { data, error } = await context.adminClient
    .from("posts")
    .update({
      status,
      moderated_by: context.admin.id,
      moderated_at: new Date().toISOString(),
      moderation_reason: status === "hidden" ? reason ?? "Hidden by admin" : null,
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydratePosts(context, [data]))[0];
}

async function bulkModeratePosts(context: AdminContext, params: Record<string, unknown>) {
  const ids = idsParam(params, "ids");
  const status = requiredStatus(params, ["published", "hidden"]);
  const reason = normalizeText(params.reason);
  const payload = {
    status,
    moderated_by: context.admin.id,
    moderated_at: new Date().toISOString(),
    moderation_reason: status === "hidden" ? reason ?? "Hidden by admin" : null,
  };

  const { data, error } = await context.adminClient
    .from("posts")
    .update(payload)
    .in("id", ids)
    .neq("status", "deleted")
    .select();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    requested: ids.length,
    updated: data?.length ?? 0,
    items: await hydratePosts(context, data ?? []),
  };
}

async function listPolls(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("community_polls")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status") ?? "pending";
  if (status === "pending") {
    query = query.or("status.eq.pending_review,deletion_status.eq.pending");
  } else if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const deletionStatus = textParam(params, "deletionStatus") ?? textParam(params, "deletion_status");
  if (deletionStatus && deletionStatus !== "all") {
    query = query.eq("deletion_status", deletionStatus);
  }

  const authorID = textParam(params, "authorID") ?? textParam(params, "author_id");
  if (authorID) {
    query = query.eq("author_id", authorID);
  }

  const search = textParam(params, "search");
  if (search) {
    const safe = likeText(search);
    query = query.or(`question.ilike.%${safe}%,detail.ilike.%${safe}%`);
  }

  query = applyCampusIDFilter(query, params);
  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    items: await hydratePolls(context, data ?? []),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function getPoll(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const { data, error } = await context.adminClient
    .from("community_polls")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  if (!data) {
    throw new HttpError(404, "Poll not found.");
  }

  return (await hydratePolls(context, [data]))[0];
}

async function moderatePoll(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["published", "hidden"]);
  const reason = normalizeText(params.reason);

  const { data: current, error: currentError } = await context.adminClient
    .from("community_polls")
    .select("id, status")
    .eq("id", id)
    .maybeSingle();

  if (currentError) {
    throw new HttpError(500, currentError.message);
  }
  if (!current) {
    throw new HttpError(404, "Poll not found.");
  }
  if (current.status === "deleted") {
    throw new HttpError(400, "Cannot moderate a poll deleted by its author.");
  }

  const { data, error } = await context.adminClient
    .from("community_polls")
    .update({
      status,
      moderated_by: context.admin.id,
      moderated_at: new Date().toISOString(),
      moderation_reason: status === "hidden" ? reason ?? "Hidden by admin" : null,
    })
    .eq("id", id)
    .neq("status", "deleted")
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydratePolls(context, [data]))[0];
}

async function reviewPollDeletion(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const decision = requiredStatus(params, ["approved", "rejected"]);
  const reason = normalizeText(params.reason);
  const now = new Date().toISOString();

  const { data: current, error: currentError } = await context.adminClient
    .from("community_polls")
    .select("id, status, deletion_status")
    .eq("id", id)
    .maybeSingle();

  if (currentError) {
    throw new HttpError(500, currentError.message);
  }
  if (!current) {
    throw new HttpError(404, "Poll not found.");
  }
  if (current.deletion_status !== "pending") {
    throw new HttpError(400, "Poll does not have a pending deletion request.");
  }

  const update = decision === "approved"
    ? {
      status: "deleted",
      deletion_status: "approved",
      deletion_reviewed_by: context.admin.id,
      deletion_reviewed_at: now,
      deletion_review_reason: reason ?? "Approved by admin",
    }
    : {
      deletion_status: "rejected",
      deletion_reviewed_by: context.admin.id,
      deletion_reviewed_at: now,
      deletion_review_reason: reason ?? "Rejected by admin",
    };

  const { data, error } = await context.adminClient
    .from("community_polls")
    .update(update)
    .eq("id", id)
    .eq("deletion_status", "pending")
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydratePolls(context, [data]))[0];
}

async function listPostPins(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("community_post_pins")
    .select("*", { count: "exact" })
    .order("status", { ascending: true })
    .order("priority", { ascending: false })
    .order("starts_at", { ascending: false })
    .range(from, to);

  const postID = textParam(params, "postID") ?? textParam(params, "post_id");
  if (postID) {
    query = query.eq("post_id", postID);
  }

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const scope = textParam(params, "scope");
  if (scope && scope !== "all") {
    query = query.eq("scope", scope);
  }

  query = applyCampusIDFilter(query, params);
  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    items: await hydratePostPins(context, data ?? []),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function pinPost(context: AdminContext, params: Record<string, unknown>) {
  const postID = requiredText(params, "postID", "post_id");
  const scope = requiredText(params, "scope");
  if (!["global", "category"].includes(scope)) {
    throw new HttpError(400, `Invalid scope: ${scope}`);
  }
  const category = scope === "category" ? requiredText(params, "category") : null;
  const priority = clamp(numberParam(params, "priority") ?? 0, -1000, 1000);
  const startsAtInput = params.startsAt ?? params.starts_at;
  const endsAtInput = params.endsAt ?? params.ends_at;
  const startsAt = normalizeDate(startsAtInput) ?? new Date().toISOString();
  const endsAt = normalizeDate(endsAtInput);
  const reason = normalizeText(params.reason);

  if (normalizeText(startsAtInput) && !normalizeDate(startsAtInput)) {
    throw new HttpError(400, "Invalid pin start time.");
  }
  if (normalizeText(endsAtInput) && !endsAt) {
    throw new HttpError(400, "Invalid pin end time.");
  }
  if (endsAt && new Date(endsAt).getTime() <= new Date(startsAt).getTime()) {
    throw new HttpError(400, "Pin end time must be after start time.");
  }

  const { data: post, error: postError } = await context.adminClient
    .from("posts")
    .select("id, status, campus_id")
    .eq("id", postID)
    .maybeSingle();

  if (postError) {
    throw new HttpError(500, postError.message);
  }
  if (!post) {
    throw new HttpError(404, "Post not found.");
  }
  if (post.status !== "published") {
    throw new HttpError(400, "Only published posts can be pinned.");
  }

  const campusID = normalizeText(post.campus_id) ?? "bjfu";

  const { error: deactivateError } = await context.adminClient
    .from("community_post_pins")
    .update({ status: "inactive" })
    .eq("campus_id", campusID)
    .eq("status", "active");
  if (deactivateError) {
    throw new HttpError(500, deactivateError.message);
  }

  const payload = {
    post_id: postID,
    campus_id: campusID,
    scope,
    category,
    priority,
    starts_at: startsAt,
    ends_at: endsAt,
    status: "active",
    reason,
    created_by: context.admin.id,
  };

  const { data, error } = await context.adminClient
    .from("community_post_pins")
    .insert(payload)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydratePostPins(context, [data]))[0];
}

async function unpinPost(context: AdminContext, params: Record<string, unknown>) {
  const id = textParam(params, "id");
  const postID = textParam(params, "postID") ?? textParam(params, "post_id");
  const scope = textParam(params, "scope");
  const category = textParam(params, "category");

  if (!id && !postID) {
    throw new HttpError(400, "id or postID is required.");
  }

  let query: any = context.adminClient
    .from("community_post_pins")
    .update({ status: "inactive" })
    .eq("status", "active");

  if (id) {
    query = query.eq("id", id);
  } else {
    query = query.eq("post_id", postID);
    if (scope) {
      query = query.eq("scope", scope);
    }
    if (scope === "category") {
      query = category ? query.eq("category", category) : query.not("category", "is", null);
    } else if (scope === "global") {
      query = query.is("category", null);
    }
  }

  const { data, error } = await query.select();
  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    updated: data?.length ?? 0,
    items: await hydratePostPins(context, data ?? []),
  };
}

async function listComments(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("comments")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const postID = textParam(params, "postID");
  if (postID) {
    query = query.eq("post_id", postID);
  }

  const authorID = textParam(params, "authorID");
  if (authorID) {
    query = query.eq("author_id", authorID);
  }

  const search = textParam(params, "search");
  if (search) {
    query = query.ilike("body", `%${likeText(search)}%`);
  }

  const campusID = scopedCampusID(params);
  if (campusID) {
    const postIDs = await catalogIDsForCampus(context.adminClient, "posts", campusID);
    if (postIDs.length === 0) {
      return { items: [], total: 0, page, pageSize };
    }
    query = query.in("post_id", postIDs);
  }

  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    items: await hydrateComments(context, data ?? []),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function listModerationReports(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("community_reports")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const targetType = textParam(params, "targetType") ?? textParam(params, "target_type");
  if (targetType && targetType !== "all") {
    query = query.eq("target_type", targetType);
  }

  const search = textParam(params, "search");
  if (search) {
    const safe = likeText(search);
    query = query.or(`reason.ilike.%${safe}%,detail.ilike.%${safe}%,resolution_note.ilike.%${safe}%`);
  }

  const campusID = scopedCampusID(params);
  if (campusID) {
    const [profileIDs, postIDs] = await Promise.all([
      idsForColumn(context.adminClient, "profiles", "community_campus_id", campusID),
      idsForColumn(context.adminClient, "posts", "campus_id", campusID),
    ]);
    const commentIDs = postIDs.length > 0
      ? await idsInColumn(context.adminClient, "comments", "post_id", postIDs)
      : [];
    const clauses = [
      profileIDs.length > 0 ? `reporter_id.in.(${profileIDs.join(",")})` : null,
      profileIDs.length > 0 ? `reported_user_id.in.(${profileIDs.join(",")})` : null,
      postIDs.length > 0 ? `post_id.in.(${postIDs.join(",")})` : null,
      commentIDs.length > 0 ? `comment_id.in.(${commentIDs.join(",")})` : null,
    ].filter(Boolean);
    if (clauses.length === 0) {
      return { items: [], total: 0, page, pageSize };
    }
    query = query.or(clauses.join(","));
  }

  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    items: await hydrateReports(context, data ?? []),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function resolveModerationReport(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["reviewed", "resolved", "rejected"]);
  const resolutionNote = normalizeText(params.resolutionNote ?? params.resolution_note) ?? statusLabelForReport(status);
  const hideContent = booleanParam(params, "hideContent") ?? booleanParam(params, "hide_content") ?? status === "resolved";
  const muteUser = booleanParam(params, "muteUser") ?? booleanParam(params, "mute_user") ?? false;
  const mutedUntil = normalizeDate(params.mutedUntil ?? params.muted_until);
  const mutedReason = normalizeText(params.mutedReason ?? params.muted_reason) ?? "Community report upheld";

  const { data: report, error: reportError } = await context.adminClient
    .from("community_reports")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (reportError) {
    throw new HttpError(500, reportError.message);
  }
  if (!report) {
    throw new HttpError(404, "Moderation report not found.");
  }

  if (hideContent) {
    if (report.target_type === "post" && report.post_id) {
      const { error } = await context.adminClient
        .from("posts")
        .update({
          status: "hidden",
          moderated_by: context.admin.id,
          moderated_at: new Date().toISOString(),
          moderation_reason: resolutionNote,
        })
        .eq("id", report.post_id)
        .neq("status", "deleted");
      if (error) throw new HttpError(500, error.message);
    }

    if (report.target_type === "comment" && report.comment_id) {
      const { error } = await context.adminClient
        .from("comments")
        .update({
          status: "hidden",
          moderated_by: context.admin.id,
          moderated_at: new Date().toISOString(),
          moderation_reason: resolutionNote,
        })
        .eq("id", report.comment_id)
        .neq("status", "deleted");
      if (error) throw new HttpError(500, error.message);
    }
  }

  if (muteUser && report.reported_user_id) {
    const until = mutedUntil ?? new Date(Date.now() + 365 * 24 * 36e5).toISOString();
    const { error } = await context.adminClient
      .from("profiles")
      .update({
        muted_until: until,
        muted_reason: mutedReason,
        muted_by: context.admin.id,
        muted_at: new Date().toISOString(),
      })
      .eq("id", report.reported_user_id);
    if (error) throw new HttpError(500, error.message);
  }

  const { data, error } = await context.adminClient
    .from("community_reports")
    .update({
      status,
      resolved_by: context.admin.id,
      resolved_at: new Date().toISOString(),
      resolution_note: resolutionNote,
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydrateReports(context, [data]))[0];
}

async function moderateComment(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["published", "hidden"]);
  const reason = normalizeText(params.reason);

  const { data: current, error: currentError } = await context.adminClient
    .from("comments")
    .select("id, status")
    .eq("id", id)
    .maybeSingle();

  if (currentError) {
    throw new HttpError(500, currentError.message);
  }
  if (!current) {
    throw new HttpError(404, "Comment not found.");
  }
  if (current.status === "deleted" && status === "published") {
    throw new HttpError(400, "Cannot restore a comment deleted by its author.");
  }

  const { data, error } = await context.adminClient
    .from("comments")
    .update({
      status,
      moderated_by: context.admin.id,
      moderated_at: new Date().toISOString(),
      moderation_reason: status === "hidden" ? reason ?? "Hidden by admin" : null,
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydrateComments(context, [data]))[0];
}

async function bulkModerateComments(context: AdminContext, params: Record<string, unknown>) {
  const ids = idsParam(params, "ids");
  const status = requiredStatus(params, ["published", "hidden"]);
  const reason = normalizeText(params.reason);
  const payload = {
    status,
    moderated_by: context.admin.id,
    moderated_at: new Date().toISOString(),
    moderation_reason: status === "hidden" ? reason ?? "Hidden by admin" : null,
  };

  const { data, error } = await context.adminClient
    .from("comments")
    .update(payload)
    .in("id", ids)
    .neq("status", "deleted")
    .select();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    requested: ids.length,
    updated: data?.length ?? 0,
    items: await hydrateComments(context, data ?? []),
  };
}

async function listProfiles(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("profiles")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const search = textParam(params, "search");
  if (search) {
    const safe = likeText(search);
    query = query.or(`edu_id.ilike.%${safe}%,nickname.ilike.%${safe}%,display_name.ilike.%${safe}%,bound_email.ilike.%${safe}%`);
  }

  const complete = booleanParam(params, "complete");
  if (complete !== null) {
    query = query.eq("is_profile_complete", complete);
  }

  const muted = textParam(params, "muted");
  if (muted === "active") {
    query = query.gt("muted_until", new Date().toISOString());
  }

  query = applyCampusIDFilter(query, params, "community_campus_id");
  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  const profiles = data ?? [];
  const ids = profiles.map((profile: any) => profile.id);
  const [postCounts, commentCounts] = await Promise.all([
    countRowsByAuthor(context.adminClient, "posts", ids),
    countRowsByAuthor(context.adminClient, "comments", ids),
  ]);

  return {
    items: profiles.map((profile: any) => ({
      ...profile,
      post_count: postCounts.get(profile.id) ?? 0,
      comment_count: commentCounts.get(profile.id) ?? 0,
      is_muted: profile.muted_until ? new Date(profile.muted_until).getTime() > Date.now() : false,
    })),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function getProfile(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const { data: profile, error } = await context.adminClient
    .from("profiles")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  if (!profile) {
    throw new HttpError(404, "Profile not found.");
  }

  const [posts, comments, auditLogs, postCount, commentCount] = await Promise.all([
    listPosts(context, { authorID: id, status: "all", pageSize: 8 }),
    listComments(context, { authorID: id, status: "all", pageSize: 8 }),
    listAuditLogsForTarget(context, "profile", id),
    countRows(context.adminClient, "posts", (query) => query.eq("author_id", id)),
    countRows(context.adminClient, "comments", (query) => query.eq("author_id", id)),
  ]);

  return {
    profile: {
      ...profile,
      post_count: postCount,
      comment_count: commentCount,
      is_muted: profile.muted_until ? new Date(profile.muted_until).getTime() > Date.now() : false,
    },
    recentPosts: posts.items,
    recentComments: comments.items,
    auditLogs,
  };
}

async function listAuditLogsForTarget(context: AdminContext, targetType: string, targetID: string) {
  const { data, error } = await context.adminClient
    .from("admin_audit_logs")
    .select("*")
    .eq("target_type", targetType)
    .eq("target_id", targetID)
    .order("created_at", { ascending: false })
    .limit(8);

  if (error) {
    throw new HttpError(500, error.message);
  }

  const adminMap = await fetchAdminMap(context.adminClient, (data ?? []).map((item: any) => item.admin_id).filter(Boolean));
  return (data ?? []).map((item: any) => ({ ...item, admin: adminMap.get(item.admin_id) ?? null }));
}

async function muteProfile(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const mutedUntil = normalizeDate(params.mutedUntil ?? params.muted_until);
  const reason = normalizeText(params.reason) ?? "Muted by admin";

  if (!mutedUntil || new Date(mutedUntil).getTime() <= Date.now()) {
    throw new HttpError(400, "Muted until must be a future time.");
  }

  const { data, error } = await context.adminClient
    .from("profiles")
    .update({
      muted_until: mutedUntil,
      muted_reason: reason,
      muted_by: context.admin.id,
      muted_at: new Date().toISOString(),
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function unmuteProfile(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const { data, error } = await context.adminClient
    .from("profiles")
    .update({
      muted_until: null,
      muted_reason: null,
      muted_by: null,
      muted_at: null,
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function listFeedback(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("feedback_submissions")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const issueType = textParam(params, "issueType");
  if (issueType) {
    query = query.eq("issue_type", issueType);
  }

  const search = textParam(params, "search");
  if (search) {
    const safe = likeText(search);
    query = query.or(`body.ilike.%${safe}%,contact.ilike.%${safe}%,issue_type.ilike.%${safe}%`);
  }

  query = applyCampusIDFilter(query, params);
  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  const profiles = await fetchProfileMap(context.adminClient, (data ?? []).map((item: any) => item.user_id).filter(Boolean));
  return {
    items: (data ?? []).map((item: any) => ({ ...item, user: profiles.get(item.user_id) ?? null })),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function updateFeedback(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["open", "reviewed", "closed"]);
  const note = normalizeText(params.adminNote ?? params.admin_note);

  const { data, error } = await context.adminClient
    .from("feedback_submissions")
    .update({
      status,
      admin_note: note,
      reviewed_by: context.admin.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function listAnnouncements(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("site_announcements")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const search = textParam(params, "search");
  if (search) {
    const safe = likeText(search);
    query = query.or(`title.ilike.%${safe}%,body.ilike.%${safe}%`);
  }

  query = applyCampusIDFilter(query, params);
  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return { items: data ?? [], total: count ?? 0, page, pageSize };
}

async function createAnnouncement(context: AdminContext, params: Record<string, unknown>) {
  const payload = normalizeAnnouncementPayload(params, false);
  const { data, error } = await context.adminClient
    .from("site_announcements")
    .insert({
      ...payload,
      created_by: context.admin.id,
      updated_by: context.admin.id,
    })
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function updateAnnouncement(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const { data: current, error: currentError } = await context.adminClient
    .from("site_announcements")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (currentError) {
    throw new HttpError(500, currentError.message);
  }
  if (!current) {
    throw new HttpError(404, "Announcement not found.");
  }

  const payload = normalizeAnnouncementPayload(params, true, current);
  const { data, error } = await context.adminClient
    .from("site_announcements")
    .update({ ...payload, updated_by: context.admin.id })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function listPostgraduateSources(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("postgraduate_sources")
    .select("*", { count: "exact" })
    .order("verified_at", { ascending: false, nullsFirst: false })
    .order("published_at", { ascending: false, nullsFirst: false })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const kind = textParam(params, "kind") ?? textParam(params, "sourceKind") ?? textParam(params, "source_kind");
  if (kind && kind !== "all") {
    query = query.eq("source_kind", kind);
  }

  const trustLevel = textParam(params, "trustLevel") ?? textParam(params, "trust_level");
  if (trustLevel && trustLevel !== "all") {
    query = query.eq("trust_level", trustLevel);
  }

  const search = textParam(params, "search");
  if (search) {
    query = query.ilike("search_text", `%${likeText(search).toLowerCase()}%`);
  }

  query = applyCampusIDFilter(query, params);
  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return { items: data ?? [], total: count ?? 0, page, pageSize };
}

async function upsertPostgraduateSource(context: AdminContext, params: Record<string, unknown>) {
  const id = textParam(params, "id");
  const payload = normalizePostgraduateSourcePayload(params, false);
  const query = id
    ? context.adminClient
      .from("postgraduate_sources")
      .update({ ...payload, updated_by: context.admin.id })
      .eq("id", id)
    : context.adminClient
      .from("postgraduate_sources")
      .insert({ ...payload, created_by: context.admin.id, updated_by: context.admin.id });

  const { data, error } = await query.select().single();
  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function setPostgraduateSourceStatus(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["published", "hidden", "archived"]);
  const { data, error } = await context.adminClient
    .from("postgraduate_sources")
    .update({ status, updated_by: context.admin.id })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function listPostgraduateSuggestions(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("postgraduate_source_suggestions")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const kind = textParam(params, "kind") ?? textParam(params, "sourceKind") ?? textParam(params, "source_kind");
  if (kind && kind !== "all") {
    query = query.eq("source_kind", kind);
  }

  const search = textParam(params, "search");
  if (search) {
    query = query.ilike("search_text", `%${likeText(search).toLowerCase()}%`);
  }

  query = applyCampusIDFilter(query, params);
  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    items: await hydratePostgraduateSuggestions(context, data ?? []),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function approvePostgraduateSuggestion(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const adminNote = normalizeText(params.adminNote ?? params.admin_note);
  const summary = normalizeText(params.summary);
  const suggestion = await fetchPostgraduateSuggestion(context, id);
  if (suggestion.status !== "open") {
    throw new HttpError(400, "Suggestion has already been reviewed.");
  }

  const sourcePayload = normalizePostgraduateSourcePayload({
    title: suggestion.title,
    summary: summary ?? suggestion.note ?? "",
    source_url: suggestion.source_url,
    sourceKind: suggestion.source_kind,
    trustLevel: "verified_user",
    school: suggestion.school,
    unit: suggestion.unit,
    major: suggestion.major,
    examYear: suggestion.exam_year,
    status: "published",
    verifiedAt: new Date().toISOString(),
  }, false);

  const { data: source, error: sourceError } = await context.adminClient
    .from("postgraduate_sources")
    .insert({
      ...sourcePayload,
      created_by: context.admin.id,
      updated_by: context.admin.id,
    })
    .select()
    .single();

  if (sourceError) {
    throw new HttpError(500, sourceError.message);
  }

  const { data, error } = await context.adminClient
    .from("postgraduate_source_suggestions")
    .update({
      status: "approved",
      approved_source_id: source.id,
      admin_note: adminNote,
      reviewed_by: context.admin.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydratePostgraduateSuggestions(context, [data]))[0];
}

async function rejectPostgraduateSuggestion(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const adminNote = normalizeText(params.adminNote ?? params.admin_note);
  const suggestion = await fetchPostgraduateSuggestion(context, id);
  if (suggestion.status !== "open") {
    throw new HttpError(400, "Suggestion has already been reviewed.");
  }

  const { data, error } = await context.adminClient
    .from("postgraduate_source_suggestions")
    .update({
      status: "rejected",
      admin_note: adminNote,
      reviewed_by: context.admin.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydratePostgraduateSuggestions(context, [data]))[0];
}

async function fetchPostgraduateSuggestion(context: AdminContext, id: string) {
  const { data, error } = await context.adminClient
    .from("postgraduate_source_suggestions")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  if (!data) {
    throw new HttpError(404, "Postgraduate suggestion not found.");
  }

  return data;
}

async function listCatalogSuggestions(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("catalog_suggestions")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const type = textParam(params, "type") ?? textParam(params, "suggestionType") ?? textParam(params, "suggestion_type");
  if (type && type !== "all") {
    query = query.eq("suggestion_type", type);
  }

  const search = textParam(params, "search");
  if (search) {
    query = query.ilike("search_text", `%${likeText(search).toLowerCase()}%`);
  }

  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return {
    items: await hydrateCatalogSuggestions(context, data ?? []),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function approveCatalogSuggestion(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const adminNote = normalizeText(params.adminNote ?? params.admin_note);
  const suggestion = await fetchCatalogSuggestion(context, id);
  if (suggestion.status !== "open") {
    throw new HttpError(400, "Suggestion has already been reviewed.");
  }

  let approvedTeacherID: number | null = null;
  let approvedCourseID: number | null = null;
  let approvedDishID: number | null = null;

  if (suggestion.suggestion_type === "teacher") {
    const teacher = await approveTeacherSuggestion(context, suggestion);
    approvedTeacherID = Number(teacher.id);
    await applyInitialTeacherRating(context, suggestion, approvedTeacherID);
  } else if (suggestion.suggestion_type === "course") {
    const course = await approveCourseSuggestion(context, suggestion);
    approvedCourseID = Number(course.id);
    await applyInitialCourseRating(context, suggestion, approvedCourseID);
  } else if (suggestion.suggestion_type === "dish") {
    const dish = await approveDishSuggestion(context, suggestion);
    approvedDishID = Number(dish.id);
    await applyInitialDishRating(context, suggestion, approvedDishID);
  } else {
    throw new HttpError(400, "Invalid suggestion type.");
  }

  const { data, error } = await context.adminClient
    .from("catalog_suggestions")
    .update({
      status: "approved",
      approved_teacher_id: approvedTeacherID,
      approved_course_id: approvedCourseID,
      approved_dish_id: approvedDishID,
      admin_note: adminNote,
      reviewed_by: context.admin.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydrateCatalogSuggestions(context, [data]))[0];
}

async function rejectCatalogSuggestion(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const adminNote = normalizeText(params.adminNote ?? params.admin_note);
  const suggestion = await fetchCatalogSuggestion(context, id);
  if (suggestion.status !== "open") {
    throw new HttpError(400, "Suggestion has already been reviewed.");
  }

  const { data, error } = await context.adminClient
    .from("catalog_suggestions")
    .update({
      status: "rejected",
      admin_note: adminNote,
      reviewed_by: context.admin.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return (await hydrateCatalogSuggestions(context, [data]))[0];
}

async function fetchCatalogSuggestion(context: AdminContext, id: string) {
  const { data, error } = await context.adminClient
    .from("catalog_suggestions")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  if (!data) {
    throw new HttpError(404, "Suggestion not found.");
  }

  return data;
}

async function approveTeacherSuggestion(context: AdminContext, suggestion: any) {
  const campusID = normalizeText(suggestion.campus_id) ?? "bjfu";
  const { data: existing, error: findError } = await context.adminClient
    .from("teachers")
    .select("*")
    .eq("campus_id", campusID)
    .eq("name", suggestion.name)
    .eq("unit", suggestion.unit)
    .maybeSingle();

  if (findError) {
    throw new HttpError(500, findError.message);
  }

  if (existing) {
    const { data, error } = await context.adminClient
      .from("teachers")
      .update({ status: "published" })
      .eq("id", existing.id)
      .select()
      .single();
    if (error) {
      throw new HttpError(500, error.message);
    }
    return data;
  }

  const { data, error } = await context.adminClient
    .from("teachers")
    .insert({ campus_id: campusID, name: suggestion.name, unit: suggestion.unit, status: "published" })
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }
  return data;
}

async function approveCourseSuggestion(context: AdminContext, suggestion: any) {
  const campusID = normalizeText(suggestion.campus_id) ?? "bjfu";
  const category = normalizeText(suggestion.category) ?? "公选课";
  const { data: existing, error: findError } = await context.adminClient
    .from("course_catalog")
    .select("*")
    .eq("campus_id", campusID)
    .eq("name", suggestion.name)
    .eq("unit", suggestion.unit)
    .eq("category", category)
    .maybeSingle();

  if (findError) {
    throw new HttpError(500, findError.message);
  }

  if (existing) {
    const payload: Record<string, unknown> = { status: "published" };
    if (suggestion.credit !== null && suggestion.credit !== undefined) {
      payload.credit = suggestion.credit;
    }

    const { data, error } = await context.adminClient
      .from("course_catalog")
      .update(payload)
      .eq("id", existing.id)
      .select()
      .single();
    if (error) {
      throw new HttpError(500, error.message);
    }
    return data;
  }

  const { data, error } = await context.adminClient
    .from("course_catalog")
    .insert({
      campus_id: campusID,
      name: suggestion.name,
      unit: suggestion.unit,
      category,
      credit: suggestion.credit ?? 0,
      status: "published",
    })
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }
  return data;
}

async function approveDishSuggestion(context: AdminContext, suggestion: any) {
  const campusID = normalizeText(suggestion.campus_id) ?? "bjfu";
  const { data: existing, error: findError } = await context.adminClient
    .from("dish_catalog")
    .select("*")
    .eq("campus_id", campusID)
    .eq("name", suggestion.name)
    .eq("location", suggestion.unit)
    .maybeSingle();

  if (findError) {
    throw new HttpError(500, findError.message);
  }

  if (existing) {
    const { data, error } = await context.adminClient
      .from("dish_catalog")
      .update({ status: "published" })
      .eq("id", existing.id)
      .select()
      .single();
    if (error) {
      throw new HttpError(500, error.message);
    }
    return data;
  }

  const { data, error } = await context.adminClient
    .from("dish_catalog")
    .insert({ campus_id: campusID, name: suggestion.name, location: suggestion.unit, status: "published" })
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }
  return data;
}

async function applyInitialTeacherRating(context: AdminContext, suggestion: any, teacherID: number) {
  const stars = initialStarsFromSuggestion(suggestion);
  if (stars === null || !suggestion.user_id) {
    return;
  }

  const { error } = await context.adminClient
    .from("teacher_ratings")
    .upsert(
      { teacher_id: teacherID, user_id: suggestion.user_id, stars },
      { onConflict: "teacher_id,user_id" },
    );

  if (error) {
    throw new HttpError(500, error.message);
  }
}

async function applyInitialCourseRating(context: AdminContext, suggestion: any, courseID: number) {
  const stars = initialStarsFromSuggestion(suggestion);
  if (stars === null || !suggestion.user_id) {
    return;
  }

  const { error } = await context.adminClient
    .from("course_ratings")
    .upsert(
      { course_id: courseID, user_id: suggestion.user_id, stars },
      { onConflict: "course_id,user_id" },
    );

  if (error) {
    throw new HttpError(500, error.message);
  }
}

async function applyInitialDishRating(context: AdminContext, suggestion: any, dishID: number) {
  const stars = initialStarsFromSuggestion(suggestion);
  if (stars === null || !suggestion.user_id) {
    return;
  }

  const { error } = await context.adminClient
    .from("dish_ratings")
    .upsert(
      { dish_id: dishID, user_id: suggestion.user_id, stars },
      { onConflict: "dish_id,user_id" },
    );

  if (error) {
    throw new HttpError(500, error.message);
  }
}

function initialStarsFromSuggestion(suggestion: any) {
  const stars = Number(suggestion.initial_stars);
  if (!Number.isInteger(stars)) {
    return null;
  }
  if (stars < 1 || stars > 5) {
    throw new HttpError(400, "Invalid initial stars.");
  }
  return stars;
}

async function listTeachers(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("teachers")
    .select("*", { count: "exact" })
    .order("rating_average", { ascending: false })
    .order("rating_count", { ascending: false })
    .order("name", { ascending: true })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const search = textParam(params, "search");
  if (search) {
    query = query.ilike("search_text", `%${likeText(search).toLowerCase()}%`);
  }

  query = applyCampusIDFilter(query, params);
  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return { items: data ?? [], total: count ?? 0, page, pageSize };
}

async function upsertTeacher(context: AdminContext, params: Record<string, unknown>) {
  const id = textParam(params, "id");
  const name = requiredText(params, "name");
  const unit = requiredText(params, "unit");
  const status = textParam(params, "status") ?? "published";
  if (!["published", "hidden"].includes(status)) {
    throw new HttpError(400, "Invalid teacher status.");
  }

  const campusID = scopedCampusID(params);
  const payload = campusID ? { name, unit, status, campus_id: campusID } : { name, unit, status };
  const query = id
    ? context.adminClient.from("teachers").update(payload).eq("id", id)
    : context.adminClient.from("teachers").insert(payload);

  const { data, error } = await query.select().single();
  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function setTeacherStatus(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["published", "hidden"]);
  const { data, error } = await context.adminClient
    .from("teachers")
    .update({ status })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function listCourses(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("course_catalog")
    .select("*", { count: "exact" })
    .order("rating_average", { ascending: false })
    .order("rating_count", { ascending: false })
    .order("name", { ascending: true })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const category = textParam(params, "category");
  if (category) {
    query = query.eq("category", category);
  }

  const search = textParam(params, "search");
  if (search) {
    query = query.ilike("search_text", `%${likeText(search).toLowerCase()}%`);
  }

  query = applyCampusIDFilter(query, params);
  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return { items: data ?? [], total: count ?? 0, page, pageSize };
}

async function upsertCourse(context: AdminContext, params: Record<string, unknown>) {
  const id = textParam(params, "id");
  const name = requiredText(params, "name");
  const unit = requiredText(params, "unit");
  const category = textParam(params, "category") ?? "公选课";
  const credit = decimalParam(params, "credit") ?? 0;
  const status = textParam(params, "status") ?? "published";
  if (!["published", "hidden"].includes(status)) {
    throw new HttpError(400, "Invalid course status.");
  }
  if (credit < 0) {
    throw new HttpError(400, "Credit cannot be negative.");
  }

  const campusID = scopedCampusID(params);
  const payload = campusID
    ? { name, unit, category, credit, status, campus_id: campusID }
    : { name, unit, category, credit, status };
  const query = id
    ? context.adminClient.from("course_catalog").update(payload).eq("id", id)
    : context.adminClient.from("course_catalog").insert(payload);

  const { data, error } = await query.select().single();
  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function setCourseStatus(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["published", "hidden"]);
  const { data, error } = await context.adminClient
    .from("course_catalog")
    .update({ status })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function listSemesterRuntimeConfigs(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("semester_runtime_configs")
    .select("*", { count: "exact" })
    .order("is_active", { ascending: false })
    .order("updated_at", { ascending: false })
    .range(from, to);

  query = applyCampusIDFilter(query, params);

  const { data, count, error } = await query;

  if (error) {
    throw new HttpError(500, error.message);
  }

  return { items: data ?? [], total: count ?? 0, page, pageSize };
}

async function upsertSemesterRuntimeConfig(context: AdminContext, params: Record<string, unknown>) {
  const id = textParam(params, "id");
  const semesterID = requiredText(params, "semesterID", "semester_id");
  const semesterStartDate = requiredDateOnly(params, "semesterStartDate", "semester_start_date");
  const supportedWeeks = numberParam(params, "supportedWeeks") ?? numberParam(params, "supported_weeks") ?? 20;
  const graduateTimetableTermCode = requiredText(params, "graduateTimetableTermCode", "graduate_timetable_term_code");
  const calendarEvents = calendarEventsParam(params);
  const isActive = booleanParam(params, "isActive") ?? booleanParam(params, "is_active");

  if (supportedWeeks < 1 || supportedWeeks > 30) {
    throw new HttpError(400, "Supported weeks must be between 1 and 30.");
  }

  const payload: Record<string, unknown> = {
    semester_id: semesterID,
    semester_start_date: semesterStartDate,
    supported_weeks: supportedWeeks,
    graduate_timetable_term_code: graduateTimetableTermCode,
    calendar_events: calendarEvents,
    updated_by: context.admin.id,
  };
  const campusID = scopedCampusID(params);
  if (campusID) {
    payload.campus_id = campusID;
  }
  if (!id || isActive !== null) {
    payload.is_active = isActive === true ? false : isActive ?? false;
  }

  const query = id
    ? context.adminClient.from("semester_runtime_configs").update(payload).eq("id", id)
    : context.adminClient.from("semester_runtime_configs").insert({ ...payload, created_by: context.admin.id });

  const { data: saved, error } = await query.select().single();
  if (error) {
    throw new HttpError(500, error.message);
  }

  if (!isActive) {
    return saved;
  }

  const { error: deactivateError } = await context.adminClient
    .from("semester_runtime_configs")
    .update({ is_active: false, updated_by: context.admin.id })
    .neq("id", saved.id);

  if (deactivateError) {
    throw new HttpError(500, deactivateError.message);
  }

  const { data: active, error: activateError } = await context.adminClient
    .from("semester_runtime_configs")
    .update({ is_active: true, updated_by: context.admin.id })
    .eq("id", saved.id)
    .select()
    .single();

  if (activateError) {
    throw new HttpError(500, activateError.message);
  }

  return active;
}

async function listDishes(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("dish_catalog")
    .select("*", { count: "exact" })
    .order("rating_average", { ascending: false })
    .order("rating_count", { ascending: false })
    .order("name", { ascending: true })
    .range(from, to);

  const status = textParam(params, "status");
  if (status && status !== "all") {
    query = query.eq("status", status);
  }

  const location = textParam(params, "location");
  if (location) {
    query = query.eq("location", location);
  }

  const search = textParam(params, "search");
  if (search) {
    query = query.ilike("search_text", `%${likeText(search).toLowerCase()}%`);
  }

  query = applyCampusIDFilter(query, params);
  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return { items: data ?? [], total: count ?? 0, page, pageSize };
}

async function upsertDish(context: AdminContext, params: Record<string, unknown>) {
  const id = textParam(params, "id");
  const name = requiredText(params, "name");
  const location = requiredText(params, "location");
  const status = textParam(params, "status") ?? "published";
  if (!["published", "hidden"].includes(status)) {
    throw new HttpError(400, "Invalid dish status.");
  }

  const campusID = scopedCampusID(params);
  const payload = campusID ? { name, location, status, campus_id: campusID } : { name, location, status };
  const query = id
    ? context.adminClient.from("dish_catalog").update(payload).eq("id", id)
    : context.adminClient.from("dish_catalog").insert(payload);

  const { data, error } = await query.select().single();
  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function setDishStatus(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const status = requiredStatus(params, ["published", "hidden"]);
  const { data, error } = await context.adminClient
    .from("dish_catalog")
    .update({ status })
    .eq("id", id)
    .select()
    .single();

  if (error) {
    throw new HttpError(500, error.message);
  }

  return data;
}

async function listTeacherRatings(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("teacher_ratings")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const teacherID = textParam(params, "teacherID") ?? textParam(params, "teacher_id");
  if (teacherID) {
    query = query.eq("teacher_id", teacherID);
  }

  const userID = textParam(params, "userID") ?? textParam(params, "user_id");
  if (userID) {
    query = query.eq("user_id", userID);
  }

  const stars = numberParam(params, "stars");
  if (stars !== null) {
    query = query.eq("stars", stars);
  }

  const campusID = scopedCampusID(params);
  if (campusID) {
    const teacherIDs = await catalogIDsForCampus(context.adminClient, "teachers", campusID);
    if (teacherIDs.length === 0) {
      return { items: [], total: 0, page, pageSize };
    }
    query = query.in("teacher_id", teacherIDs);
  }

  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  const teacherMap = await fetchTeacherMap(context.adminClient, (data ?? []).map((item: any) => item.teacher_id));
  const profileMap = await fetchProfileMap(context.adminClient, (data ?? []).map((item: any) => item.user_id));

  return {
    items: (data ?? []).map((item: any) => ({
      ...item,
      teacher: teacherMap.get(String(item.teacher_id)) ?? null,
      user: profileMap.get(item.user_id) ?? null,
    })),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function listDishRatings(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("dish_ratings")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const dishID = textParam(params, "dishID") ?? textParam(params, "dish_id");
  if (dishID) {
    query = query.eq("dish_id", dishID);
  }

  const userID = textParam(params, "userID") ?? textParam(params, "user_id");
  if (userID) {
    query = query.eq("user_id", userID);
  }

  const stars = numberParam(params, "stars");
  if (stars !== null) {
    query = query.eq("stars", stars);
  }

  const campusID = scopedCampusID(params);
  if (campusID) {
    const dishIDs = await catalogIDsForCampus(context.adminClient, "dish_catalog", campusID);
    if (dishIDs.length === 0) {
      return { items: [], total: 0, page, pageSize };
    }
    query = query.in("dish_id", dishIDs);
  }

  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  const dishMap = await fetchDishMap(context.adminClient, (data ?? []).map((item: any) => item.dish_id));
  const profileMap = await fetchProfileMap(context.adminClient, (data ?? []).map((item: any) => item.user_id));

  return {
    items: (data ?? []).map((item: any) => ({
      ...item,
      dish: dishMap.get(String(item.dish_id)) ?? null,
      user: profileMap.get(item.user_id) ?? null,
    })),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function deleteTeacherRating(context: AdminContext, params: Record<string, unknown>) {
  const teacherID = requiredText(params, "teacherID", "teacher_id");
  const userID = requiredText(params, "userID", "user_id");
  const { error } = await context.adminClient
    .from("teacher_ratings")
    .delete()
    .eq("teacher_id", teacherID)
    .eq("user_id", userID);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return { teacher_id: teacherID, user_id: userID };
}

async function deleteDishRating(context: AdminContext, params: Record<string, unknown>) {
  const dishID = requiredText(params, "dishID", "dish_id");
  const userID = requiredText(params, "userID", "user_id");
  const { error } = await context.adminClient
    .from("dish_ratings")
    .delete()
    .eq("dish_id", dishID)
    .eq("user_id", userID);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return { dish_id: dishID, user_id: userID };
}

async function listAdmins(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("admin_accounts")
    .select("id, username, display_name, role, active, last_login_at, created_at, updated_at", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const search = textParam(params, "search");
  if (search) {
    const safe = likeText(search);
    query = query.or(`username.ilike.%${safe}%,display_name.ilike.%${safe}%`);
  }

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return { items: data ?? [], total: count ?? 0, page, pageSize };
}

async function createAdmin(context: AdminContext, params: Record<string, unknown>) {
  const username = requiredText(params, "username");
  const password = requiredText(params, "password");
  const displayName = normalizeText(params.displayName ?? params.display_name) ?? username;
  const role = textParam(params, "role") ?? "operator";

  const { data, error } = await context.adminClient.rpc("admin_create_account", {
    p_username: username,
    p_password: password,
    p_display_name: displayName,
    p_role: role,
    p_created_by: context.admin.id,
  });

  if (error) {
    throw new HttpError(500, error.message);
  }

  return Array.isArray(data) ? data[0] : data;
}

async function updateAdmin(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const { data, error } = await context.adminClient.rpc("admin_update_account", {
    p_account_id: id,
    p_actor_id: context.admin.id,
    p_username: normalizeText(params.username),
    p_password: normalizeText(params.password),
    p_display_name: normalizeText(params.displayName ?? params.display_name),
    p_role: normalizeText(params.role),
    p_active: booleanParam(params, "active"),
  });

  if (error) {
    throw new HttpError(500, error.message);
  }

  return Array.isArray(data) ? data[0] : data;
}

async function disableAdmin(context: AdminContext, params: Record<string, unknown>) {
  const id = requiredText(params, "id");
  const { data, error } = await context.adminClient.rpc("admin_update_account", {
    p_account_id: id,
    p_actor_id: context.admin.id,
    p_active: false,
  });

  if (error) {
    throw new HttpError(500, error.message);
  }

  return Array.isArray(data) ? data[0] : data;
}

async function listAuditLogs(context: AdminContext, params: Record<string, unknown>) {
  const { from, to, page, pageSize } = pagination(params);
  let query: any = context.adminClient
    .from("admin_audit_logs")
    .select("*", { count: "exact" })
    .order("created_at", { ascending: false })
    .range(from, to);

  const adminID = textParam(params, "adminID") ?? textParam(params, "admin_id");
  if (adminID) {
    query = query.eq("admin_id", adminID);
  }

  const action = textParam(params, "action");
  if (action) {
    query = query.ilike("action", `%${likeText(action)}%`);
  }

  query = applyDateFilters(query, params, "created_at");

  const { data, count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  const adminMap = await fetchAdminMap(context.adminClient, (data ?? []).map((item: any) => item.admin_id).filter(Boolean));
  return {
    items: (data ?? []).map((item: any) => ({ ...item, admin: adminMap.get(item.admin_id) ?? null })),
    total: count ?? 0,
    page,
    pageSize,
  };
}

async function hydratePosts(context: AdminContext, posts: any[], includeSignedImages = false) {
  const authorMap = await fetchProfileMap(context.adminClient, posts.map((post) => post.author_id));
  const imageMap = await fetchPostImageMap(context.adminClient, posts.map((post) => post.id), includeSignedImages);
  const likeMap = await countPostLikes(context.adminClient, posts.map((post) => post.id));
  const pinMap = await fetchPostPinMap(context.adminClient, posts.map((post) => post.id));

  return posts.map((post) => ({
    ...post,
    author: authorMap.get(post.author_id) ?? null,
    images: imageMap.get(post.id) ?? [],
    like_count: likeMap.get(post.id) ?? 0,
    pin: pinMap.get(post.id) ?? null,
  }));
}

async function hydratePolls(context: AdminContext, polls: any[]) {
  const authorMap = await fetchProfileMap(context.adminClient, polls.map((poll) => poll.author_id));
  const optionMap = await fetchPollOptionMap(context.adminClient, polls.map((poll) => poll.id));
  const moderatorMap = await fetchAdminMap(context.adminClient, polls.map((poll) => poll.moderated_by).filter(Boolean));

  return polls.map((poll) => ({
    ...poll,
    author: authorMap.get(poll.author_id) ?? null,
    options: optionMap.get(poll.id) ?? [],
    moderator: poll.moderated_by ? moderatorMap.get(poll.moderated_by) ?? null : null,
  }));
}

async function hydratePostPins(context: AdminContext, pins: any[]) {
  const postMap = await fetchPostMap(context.adminClient, pins.map((pin) => pin.post_id));
  const adminMap = await fetchAdminMap(context.adminClient, pins.map((pin) => pin.created_by).filter(Boolean));

  return pins.map((pin) => ({
    ...pin,
    post: postMap.get(pin.post_id) ?? null,
    admin: pin.created_by ? adminMap.get(pin.created_by) ?? null : null,
  }));
}

async function hydrateComments(context: AdminContext, comments: any[]) {
  const authorMap = await fetchProfileMap(context.adminClient, comments.map((comment) => comment.author_id));
  const postMap = await fetchPostTitleMap(context.adminClient, comments.map((comment) => comment.post_id));

  return comments.map((comment) => ({
    ...comment,
    author: authorMap.get(comment.author_id) ?? null,
    post: postMap.get(comment.post_id) ?? null,
  }));
}

async function hydrateReports(context: AdminContext, reports: any[]) {
  const reporterMap = await fetchProfileMap(context.adminClient, reports.map((report) => report.reporter_id));
  const reportedUserMap = await fetchProfileMap(context.adminClient, reports.map((report) => report.reported_user_id).filter(Boolean));
  const postMap = await fetchPostMap(context.adminClient, reports.map((report) => report.post_id).filter(Boolean));
  const commentMap = await fetchCommentMap(context.adminClient, reports.map((report) => report.comment_id).filter(Boolean));
  const adminMap = await fetchAdminMap(context.adminClient, reports.map((report) => report.resolved_by).filter(Boolean));

  return reports.map((report) => ({
    ...report,
    reporter: reporterMap.get(report.reporter_id) ?? null,
    reported_user: report.reported_user_id ? reportedUserMap.get(report.reported_user_id) ?? null : null,
    post: report.post_id ? postMap.get(report.post_id) ?? null : null,
    comment: report.comment_id ? commentMap.get(report.comment_id) ?? null : null,
    resolver: report.resolved_by ? adminMap.get(report.resolved_by) ?? null : null,
  }));
}

async function hydrateCatalogSuggestions(context: AdminContext, suggestions: any[]) {
  const userMap = await fetchProfileMap(context.adminClient, suggestions.map((item) => item.user_id).filter(Boolean));
  const reviewerMap = await fetchAdminMap(context.adminClient, suggestions.map((item) => item.reviewed_by).filter(Boolean));
  const teacherMap = await fetchTeacherMap(context.adminClient, suggestions.map((item) => item.approved_teacher_id).filter(Boolean));
  const courseMap = await fetchCourseMap(context.adminClient, suggestions.map((item) => item.approved_course_id).filter(Boolean));
  const dishMap = await fetchDishMap(context.adminClient, suggestions.map((item) => item.approved_dish_id).filter(Boolean));

  return suggestions.map((item) => ({
    ...item,
    user: item.user_id ? userMap.get(item.user_id) ?? null : null,
    reviewer: item.reviewed_by ? reviewerMap.get(item.reviewed_by) ?? null : null,
    approved_teacher: item.approved_teacher_id ? teacherMap.get(String(item.approved_teacher_id)) ?? null : null,
    approved_course: item.approved_course_id ? courseMap.get(String(item.approved_course_id)) ?? null : null,
    approved_dish: item.approved_dish_id ? dishMap.get(String(item.approved_dish_id)) ?? null : null,
  }));
}

async function hydratePostgraduateSuggestions(context: AdminContext, suggestions: any[]) {
  const userMap = await fetchProfileMap(context.adminClient, suggestions.map((item) => item.user_id).filter(Boolean));
  const reviewerMap = await fetchAdminMap(context.adminClient, suggestions.map((item) => item.reviewed_by).filter(Boolean));
  const sourceMap = await fetchPostgraduateSourceMap(context.adminClient, suggestions.map((item) => item.approved_source_id).filter(Boolean));

  return suggestions.map((item) => ({
    ...item,
    user: item.user_id ? userMap.get(item.user_id) ?? null : null,
    reviewer: item.reviewed_by ? reviewerMap.get(item.reviewed_by) ?? null : null,
    approved_source: item.approved_source_id ? sourceMap.get(item.approved_source_id) ?? null : null,
  }));
}

async function fetchProfileMap(client: any, ids: string[]) {
  const uniqueIDs = unique(ids);
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("profiles")
    .select("*")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [item.id, item]));
}

async function fetchAdminMap(client: any, ids: string[]) {
  const uniqueIDs = unique(ids);
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("admin_accounts")
    .select("id, username, display_name, role, active")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [item.id, item]));
}

async function fetchTeacherMap(client: any, ids: Array<string | number>) {
  const uniqueIDs = unique(ids.map((id) => String(id)));
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("teachers")
    .select("*")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [String(item.id), item]));
}

async function fetchCourseMap(client: any, ids: Array<string | number>) {
  const uniqueIDs = unique(ids.map((id) => String(id)));
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("course_catalog")
    .select("*")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [String(item.id), item]));
}

async function fetchDishMap(client: any, ids: Array<string | number>) {
  const uniqueIDs = unique(ids.map((id) => String(id)));
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("dish_catalog")
    .select("*")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [String(item.id), item]));
}

async function fetchPostgraduateSourceMap(client: any, ids: string[]) {
  const uniqueIDs = unique(ids);
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("postgraduate_sources")
    .select("*")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [item.id, item]));
}

async function fetchPostTitleMap(client: any, ids: string[]) {
  const uniqueIDs = unique(ids);
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("posts")
    .select("id, title, status")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [item.id, item]));
}

async function fetchPostMap(client: any, ids: string[]) {
  const uniqueIDs = unique(ids);
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("posts")
    .select("id, author_id, title, body, category, is_anonymous, status, created_at")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [item.id, item]));
}

async function fetchCommentMap(client: any, ids: string[]) {
  const uniqueIDs = unique(ids);
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("comments")
    .select("id, post_id, author_id, body, is_anonymous, status, created_at")
    .in("id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  return new Map((data ?? []).map((item: any) => [item.id, item]));
}

async function fetchPostImageMap(client: any, postIDs: string[], includeSignedImages: boolean) {
  const uniqueIDs = unique(postIDs);
  if (uniqueIDs.length === 0) {
    return new Map<string, any[]>();
  }

  const { data, error } = await client
    .from("post_images")
    .select("*")
    .in("post_id", uniqueIDs)
    .order("sort_order", { ascending: true });

  if (error) {
    throw new HttpError(500, error.message);
  }

  const images = data ?? [];
  const signedMap = new Map<string, string>();
  if (includeSignedImages) {
    const paths = unique(images.map((image: any) => image.path).filter(Boolean));
    if (paths.length > 0) {
      const { data: signed } = await client.storage
        .from("community-images")
        .createSignedUrls(paths, 60 * 60);
      for (const result of signed ?? []) {
        signedMap.set(result.path, result.signedUrl ?? result.signedURL);
      }
    }
  }

  const grouped = new Map<string, any[]>();
  for (const image of images) {
    const list = grouped.get(image.post_id) ?? [];
    list.push({ ...image, signed_url: signedMap.get(image.path) ?? null });
    grouped.set(image.post_id, list);
  }
  return grouped;
}

async function fetchPollOptionMap(client: any, pollIDs: string[]) {
  const uniqueIDs = unique(pollIDs);
  const grouped = new Map<string, any[]>();
  if (uniqueIDs.length === 0) {
    return grouped;
  }

  const { data, error } = await client
    .from("community_poll_options")
    .select("*")
    .in("poll_id", uniqueIDs)
    .order("sort_order", { ascending: true });

  if (error) {
    throw new HttpError(500, error.message);
  }

  for (const option of data ?? []) {
    const list = grouped.get(option.poll_id) ?? [];
    list.push(option);
    grouped.set(option.poll_id, list);
  }
  return grouped;
}

async function countPostLikes(client: any, postIDs: string[]) {
  const uniqueIDs = unique(postIDs);
  const counts = new Map<string, number>();
  if (uniqueIDs.length === 0) {
    return counts;
  }

  const { data, error } = await client
    .from("post_likes")
    .select("post_id")
    .in("post_id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  for (const like of data ?? []) {
    counts.set(like.post_id, (counts.get(like.post_id) ?? 0) + 1);
  }
  return counts;
}

async function fetchPostPinMap(client: any, postIDs: string[]) {
  const uniqueIDs = unique(postIDs);
  if (uniqueIDs.length === 0) {
    return new Map<string, any>();
  }

  const { data, error } = await client
    .from("community_post_pins")
    .select("*")
    .in("post_id", uniqueIDs)
    .eq("status", "active")
    .lte("starts_at", new Date().toISOString())
    .order("priority", { ascending: false })
    .order("starts_at", { ascending: false });

  if (error) {
    if (String(error.message ?? "").includes("community_post_pins")) {
      return new Map<string, any>();
    }
    throw new HttpError(500, error.message);
  }

  const now = Date.now();
  const map = new Map<string, any>();
  for (const pin of data ?? []) {
    if (pin.ends_at && new Date(pin.ends_at).getTime() <= now) {
      continue;
    }
    if (!map.has(pin.post_id)) {
      map.set(pin.post_id, pin);
    }
  }
  return map;
}

async function countRowsByAuthor(client: any, table: string, authorIDs: string[]) {
  const uniqueIDs = unique(authorIDs);
  const counts = new Map<string, number>();
  if (uniqueIDs.length === 0) {
    return counts;
  }

  const { data, error } = await client
    .from(table)
    .select("author_id")
    .in("author_id", uniqueIDs);

  if (error) {
    throw new HttpError(500, error.message);
  }

  for (const row of data ?? []) {
    counts.set(row.author_id, (counts.get(row.author_id) ?? 0) + 1);
  }
  return counts;
}

async function countRows(client: any, table: string, configure?: (query: any) => any) {
  let query: any = client.from(table).select("id", { count: "exact", head: true });
  if (configure) {
    query = configure(query);
  }

  const { count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return count ?? 0;
}

async function countRowsForIDs(client: any, table: string, column: string, ids: unknown[], configure?: (query: any) => any) {
  if (ids.length === 0) return 0;
  return countRows(client, table, (query) => {
    let scopedQuery = query.in(column, ids);
    if (configure) {
      scopedQuery = configure(scopedQuery);
    }
    return scopedQuery;
  });
}

async function countModerationReports(context: AdminContext, campusID: string | null, configure?: (query: any) => any) {
  let query: any = context.adminClient
    .from("community_reports")
    .select("id", { count: "exact", head: true });

  if (campusID) {
    const [profileIDs, postIDs] = await Promise.all([
      idsForColumn(context.adminClient, "profiles", "community_campus_id", campusID),
      idsForColumn(context.adminClient, "posts", "campus_id", campusID),
    ]);
    const commentIDs = postIDs.length > 0
      ? await idsInColumn(context.adminClient, "comments", "post_id", postIDs)
      : [];
    const clauses = [
      profileIDs.length > 0 ? `reporter_id.in.(${profileIDs.join(",")})` : null,
      profileIDs.length > 0 ? `reported_user_id.in.(${profileIDs.join(",")})` : null,
      postIDs.length > 0 ? `post_id.in.(${postIDs.join(",")})` : null,
      commentIDs.length > 0 ? `comment_id.in.(${commentIDs.join(",")})` : null,
    ].filter(Boolean);
    if (clauses.length === 0) return 0;
    query = query.or(clauses.join(","));
  }

  if (configure) {
    query = configure(query);
  }

  const { count, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }

  return count ?? 0;
}

function normalizeAnnouncementPayload(params: Record<string, unknown>, partial: boolean, current?: any) {
  const payload: Record<string, unknown> = {};
  const has = (key: string) => Object.prototype.hasOwnProperty.call(params, key);

  if (!partial || has("title")) {
    const title = normalizeText(params.title);
    if (!title) throw new HttpError(400, "Announcement title is required.");
    if (title.length > 120) throw new HttpError(400, "Announcement title is too long.");
    payload.title = title;
  }

  if (!partial || has("body")) {
    const body = normalizeText(params.body);
    if (!body) throw new HttpError(400, "Announcement body is required.");
    if (body.length > 4000) throw new HttpError(400, "Announcement body is too long.");
    payload.body = body;
  }

  if (!partial || has("level")) {
    const level = textParam(params, "level") ?? "info";
    if (!["info", "warning", "urgent"].includes(level)) {
      throw new HttpError(400, "Invalid announcement level.");
    }
    payload.level = level;
  }

  if (!partial || has("status")) {
    const status = textParam(params, "status") ?? "draft";
    if (!["draft", "published", "archived"].includes(status)) {
      throw new HttpError(400, "Invalid announcement status.");
    }
    payload.status = status;
  }

  if (has("published_at") || has("publishedAt")) {
    payload.published_at = normalizeDate(params.published_at ?? params.publishedAt);
  }

  if (has("expires_at") || has("expiresAt")) {
    payload.expires_at = normalizeDate(params.expires_at ?? params.expiresAt);
  }

  const campusID = scopedCampusID(params);
  if (campusID) {
    payload.campus_id = campusID;
  }

  if (payload.status === "published" && !payload.published_at && !current?.published_at) {
    payload.published_at = new Date().toISOString();
  }

  const publishedAt = payload.published_at ?? current?.published_at ?? null;
  const expiresAt = Object.prototype.hasOwnProperty.call(payload, "expires_at")
    ? payload.expires_at
    : current?.expires_at ?? null;

  if (publishedAt && expiresAt && new Date(String(expiresAt)).getTime() <= new Date(String(publishedAt)).getTime()) {
    throw new HttpError(400, "Announcement expiry must be later than publish time.");
  }

  return payload;
}

function normalizePostgraduateSourcePayload(params: Record<string, unknown>, partial: boolean) {
  const payload: Record<string, unknown> = {};
  const has = (key: string) => Object.prototype.hasOwnProperty.call(params, key);

  if (!partial || has("title")) {
    const title = normalizeText(params.title);
    if (!title) throw new HttpError(400, "Postgraduate source title is required.");
    if (title.length > 180) throw new HttpError(400, "Postgraduate source title is too long.");
    payload.title = title;
  }

  if (!partial || has("summary")) {
    const summary = normalizeText(params.summary) ?? "";
    if (summary.length > 1200) throw new HttpError(400, "Postgraduate source summary is too long.");
    payload.summary = summary;
  }

  if (!partial || has("source_url") || has("sourceURL") || has("sourceUrl")) {
    payload.source_url = requiredURL(params.source_url ?? params.sourceURL ?? params.sourceUrl, "source_url");
  }

  if (!partial || has("source_kind") || has("sourceKind")) {
    const sourceKind = normalizeText(params.source_kind ?? params.sourceKind) ?? "other";
    if (!postgraduateSourceKinds.includes(sourceKind)) {
      throw new HttpError(400, "Invalid postgraduate source kind.");
    }
    payload.source_kind = sourceKind;
  }

  if (!partial || has("trust_level") || has("trustLevel")) {
    const trustLevel = normalizeText(params.trust_level ?? params.trustLevel) ?? "curated";
    if (!postgraduateTrustLevels.includes(trustLevel)) {
      throw new HttpError(400, "Invalid postgraduate trust level.");
    }
    payload.trust_level = trustLevel;
  }

  if (!partial || has("status")) {
    const status = normalizeText(params.status) ?? "published";
    if (!["published", "hidden", "archived"].includes(status)) {
      throw new HttpError(400, "Invalid postgraduate source status.");
    }
    payload.status = status;
  }

  if (!partial || has("school")) payload.school = normalizeText(params.school);
  if (!partial || has("unit")) payload.unit = normalizeText(params.unit);
  if (!partial || has("major")) payload.major = normalizeText(params.major);

  if (!partial || has("exam_year") || has("examYear")) {
    const examYear = numberParam(params, "exam_year") ?? numberParam(params, "examYear");
    if (examYear !== null && (examYear < 2000 || examYear > 2100)) {
      throw new HttpError(400, "Invalid postgraduate exam year.");
    }
    payload.exam_year = examYear;
  }

  if (has("published_at") || has("publishedAt")) {
    payload.published_at = normalizeDate(params.published_at ?? params.publishedAt);
  }

  if (has("verified_at") || has("verifiedAt")) {
    payload.verified_at = normalizeDate(params.verified_at ?? params.verifiedAt);
  } else if (!partial && !payload.verified_at) {
    payload.verified_at = new Date().toISOString();
  }

  return payload;
}

function pagination(params: Record<string, unknown>) {
  const page = clamp(numberParam(params, "page") ?? 0, 0, 100000);
  const pageSize = clamp(numberParam(params, "pageSize") ?? numberParam(params, "page_size") ?? 20, 1, 100);
  return {
    page,
    pageSize,
    from: page * pageSize,
    to: page * pageSize + pageSize - 1,
  };
}

function applyDateFilters(query: any, params: Record<string, unknown>, column: string) {
  const start = normalizeDate(params.start ?? params.startAt ?? params.start_at);
  const end = normalizeDate(params.end ?? params.endAt ?? params.end_at);

  if (start) {
    query = query.gte(column, start);
  }
  if (end) {
    query = query.lte(column, end);
  }
  return query;
}

function requiredText(params: Record<string, unknown>, primary: string, fallback?: string) {
  const value = normalizeText(params[primary] ?? (fallback ? params[fallback] : null));
  if (!value) {
    throw new HttpError(400, `${primary} is required.`);
  }
  return value;
}

function requiredURL(value: unknown, field: string) {
  const text = normalizeText(value);
  if (!text) {
    throw new HttpError(400, `${field} is required.`);
  }

  let url: URL;
  try {
    url = new URL(text);
  } catch {
    throw new HttpError(400, `${field} must be a valid URL.`);
  }

  if (!["http:", "https:"].includes(url.protocol) || !url.hostname) {
    throw new HttpError(400, `${field} must be an HTTP URL.`);
  }

  return url.toString();
}

function requiredDateOnly(params: Record<string, unknown>, primary: string, fallback?: string) {
  const value = requiredText(params, primary, fallback);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(new Date(`${value}T00:00:00Z`).getTime())) {
    throw new HttpError(400, `${primary} must be a YYYY-MM-DD date.`);
  }
  return value;
}

function requiredStatus(params: Record<string, unknown>, allowed: string[]) {
  const status = requiredText(params, "status");
  if (!allowed.includes(status)) {
    throw new HttpError(400, `Invalid status: ${status}`);
  }
  return status;
}

function statusLabelForReport(status: string) {
  if (status === "resolved") return "Report resolved by admin.";
  if (status === "rejected") return "Report rejected by admin.";
  return "Report reviewed by admin.";
}

function textParam(params: Record<string, unknown>, key: string) {
  return normalizeText(params[key]);
}

function scopedCampusID(params: Record<string, unknown>) {
  const value = normalizeText(params.campusID ?? params.campus_id);
  if (!value || value === "all") return null;
  return value.toLowerCase();
}

function applyCampusIDFilter(query: any, params: Record<string, unknown>, column = "campus_id") {
  const campusID = scopedCampusID(params);
  return campusID ? query.eq(column, campusID) : query;
}

async function catalogIDsForCampus(client: any, table: string, campusID: string) {
  return idsForColumn(client, table, "campus_id", campusID);
}

async function idsForColumn(client: any, table: string, column: string, value: string) {
  const { data, error } = await client
    .from(table)
    .select("id")
    .eq(column, value);
  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []).map((item: any) => item.id);
}

async function idsInColumn(client: any, table: string, column: string, values: unknown[]) {
  if (values.length === 0) return [];
  const { data, error } = await client
    .from(table)
    .select("id")
    .in(column, values);
  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []).map((item: any) => item.id);
}

function normalizeSchoolName(value: string) {
  return value.trim().replace(/\s+/g, "").toLowerCase();
}

function isBJFUCampusReference(value: string) {
  const normalized = normalizeSchoolName(value);
  return normalized === "bjfu" || normalized === "北京林业大学" || normalized === "北林";
}

function campusIDFromRequest(requestID: string, displayName: string) {
  const ascii = displayName
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
  return ascii || `school-${requestID.replace(/-/g, "").slice(0, 10)}`;
}

function calendarEventsParam(params: Record<string, unknown>) {
  const raw = params.calendarEvents ?? params.calendar_events ?? [];
  let parsed = raw;
  if (typeof raw === "string") {
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw new HttpError(400, "calendarEvents must be valid JSON.");
    }
  }

  if (!Array.isArray(parsed)) {
    throw new HttpError(400, "calendarEvents must be an array.");
  }

  return parsed.map((item, index) => {
    if (!item || typeof item !== "object") {
      throw new HttpError(400, `calendarEvents[${index}] must be an object.`);
    }
    const row = item as Record<string, unknown>;
    const id = normalizeText(row.id);
    const title = normalizeText(row.title);
    const startDateString = normalizeText(row.startDateString ?? row.start_date);
    const endDateString = normalizeText(row.endDateString ?? row.end_date);
    const kind = normalizeText(row.kind);

    if (!id || !title || !startDateString || !endDateString || !kind) {
      throw new HttpError(400, `calendarEvents[${index}] is missing required fields.`);
    }
    if (!["holiday", "closure"].includes(kind)) {
      throw new HttpError(400, `calendarEvents[${index}].kind is invalid.`);
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(startDateString) || !/^\d{4}-\d{2}-\d{2}$/.test(endDateString)) {
      throw new HttpError(400, `calendarEvents[${index}] dates must use YYYY-MM-DD.`);
    }

    return { id, title, startDateString, endDateString, kind };
  });
}

function numberParam(params: Record<string, unknown>, key: string) {
  const raw = params[key];
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Math.trunc(raw);
  }
  if (typeof raw === "string" && raw.trim() !== "") {
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
  }
  return null;
}

function decimalParam(params: Record<string, unknown>, key: string) {
  const raw = params[key];
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return raw;
  }
  if (typeof raw === "string" && raw.trim() !== "") {
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function idsParam(params: Record<string, unknown>, key: string) {
  const raw = params[key];
  if (!Array.isArray(raw)) {
    throw new HttpError(400, `${key} must be an array.`);
  }

  const ids = unique(raw.map((item) => (typeof item === "string" ? item.trim() : "")).filter(Boolean));
  if (ids.length === 0) {
    throw new HttpError(400, `${key} cannot be empty.`);
  }
  if (ids.length > 100) {
    throw new HttpError(400, `${key} cannot include more than 100 records.`);
  }
  return ids;
}

function booleanParam(params: Record<string, unknown>, key: string) {
  const raw = params[key];
  if (typeof raw === "boolean") {
    return raw;
  }
  if (typeof raw === "string") {
    if (raw === "true") return true;
    if (raw === "false") return false;
  }
  return null;
}

function analyticsDays(params: Record<string, unknown>) {
  const requested = numberParam(params, "days") ?? 30;
  if (requested <= 7) return 7;
  if (requested <= 30) return 30;
  return 90;
}

function analyticsTimezone(params: Record<string, unknown>) {
  const requested = textParam(params, "timezone") ?? "UTC";
  if (requested.length > 64 || !/^[A-Za-z0-9_+\-/:]+$/.test(requested)) {
    return "UTC";
  }
  return requested;
}

function likeText(value: string) {
  return value.replace(/[,%()]/g, " ").trim();
}

function unique<T>(values: T[]) {
  return Array.from(new Set(values.filter(Boolean)));
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, value));
}

function startOfTodayISO() {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  return date.toISOString();
}

function inferTarget(action: string, params: Record<string, unknown>) {
  if (action === "bulkModeratePosts") return { type: "post", id: "bulk" };
  if (action === "bulkModerateComments") return { type: "comment", id: "bulk" };
  if (action.includes("Poll")) return { type: "poll", id: textParam(params, "id") };
  if (action === "pinPost" || action === "unpinPost") {
    return { type: "post", id: textParam(params, "postID") ?? textParam(params, "post_id") ?? textParam(params, "id") };
  }
  if (action.includes("ModerationReport")) return { type: "community_report", id: textParam(params, "id") };
  if (action.includes("Post")) return { type: "post", id: textParam(params, "id") };
  if (action.includes("Comment")) return { type: "comment", id: textParam(params, "id") };
  if (action.includes("Profile")) return { type: "profile", id: textParam(params, "id") };
  if (action.includes("Feedback")) return { type: "feedback", id: textParam(params, "id") };
  if (action.includes("Announcement")) return { type: "announcement", id: textParam(params, "id") };
  if (action.includes("PostgraduateSource")) return { type: "postgraduate_source", id: textParam(params, "id") };
  if (action.includes("PostgraduateSuggestion")) return { type: "postgraduate_source_suggestion", id: textParam(params, "id") };
  if (action.includes("CatalogSuggestion")) return { type: "catalog_suggestion", id: textParam(params, "id") };
  if (action.includes("Teacher")) return { type: "teacher", id: textParam(params, "id") ?? textParam(params, "teacherID") };
  if (action.includes("Course")) return { type: "course", id: textParam(params, "id") ?? textParam(params, "courseID") };
  if (action.includes("Dish")) return { type: "dish", id: textParam(params, "id") ?? textParam(params, "dishID") };
  if (action.includes("SemesterRuntimeConfig")) return { type: "semester_runtime_config", id: textParam(params, "id") ?? textParam(params, "semesterID") ?? textParam(params, "semester_id") };
  if (action.includes("Admin")) return { type: "admin", id: textParam(params, "id") };
  return { type: action, id: null };
}
