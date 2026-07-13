export type ColumnConfig = {
  source: string;
  label: string;
  kind?: "text" | "date" | "number" | "boolean" | "json";
  sortable?: boolean;
};

export type FormFieldConfig = {
  source: string;
  label: string;
  kind?: "text" | "longtext" | "number" | "date" | "datetime" | "boolean" | "json" | "select" | "password";
  required?: boolean;
  choices?: Array<{ id: string | number; name: string }>;
};

export type RowActionConfig = {
  label: string;
  action: string;
  tone?: "primary" | "danger";
  permissionAction?: "edit" | "delete" | "bulk";
  visible?: (record: Record<string, any>) => boolean;
  fields?: FormFieldConfig[];
  fixed?: Record<string, unknown>;
  build?: (record: Record<string, any>, values: Record<string, unknown>) => Record<string, unknown>;
};

export type ResourceConfig = {
  label: string;
  columns: ColumnConfig[];
  statusChoices?: Array<{ id: string; name: string }>;
  filters?: FormFieldConfig[];
  createForm?: FormFieldConfig[];
  editForm?: FormFieldConfig[];
  actions?: RowActionConfig[];
  exportable?: boolean;
  editable?: boolean;
  searchable?: boolean;
  defaultSort?: { field: string; order: "ASC" | "DESC" };
};

const status = (...values: string[]) => values.map((value) => ({ id: value, name: statusName(value) }));
const feedbackStatus = (...values: string[]) => values.map((value) => ({ id: value, name: ({ open: "未查看", reviewed: "已查看待处理", closed: "已完成", all: "全部" } as Record<string, string>)[value] ?? value }));
const reasonField = (label = "原因"): FormFieldConfig => ({ source: "reason", label, kind: "longtext", required: true });
const idParams = (record: Record<string, any>, values: Record<string, unknown>) => ({ id: record.id, ...values });

export const resourceConfigs: Record<string, ResourceConfig> = {
  campuses: { label: "学校空间", columns: columns(["id", "ID"], ["display_name", "学校"], ["connector_kind", "连接器"], ["is_community_enabled", "社区开放", "boolean"], ["status", "状态"]), searchable: false },
  "campus-requests": {
    label: "学校归属申请", columns: columns(["request_type", "类型"], ["school_name", "学校"], ["requester.nickname", "用户"], ["status", "状态"], ["admin_note", "审核备注"], ["created_at", "时间", "date"]), statusChoices: status("pending", "approved", "rejected", "all"),
    actions: [
      { label: "批准更换", action: "approveCampusRequest", visible: (r) => r.status === "pending" && r.request_type === "school_change", build: (r) => ({ id: r.id, campusID: r.requested_campus_id }) },
      { label: "批准为新学校", action: "approveCampusRequest", visible: (r) => r.status === "pending" && r.request_type !== "school_change", fields: [{ source: "displayName", label: "学校显示名称", required: true }], build: idParams },
      { label: "关联已有学校", action: "approveCampusRequest", visible: (r) => r.status === "pending" && r.request_type !== "school_change", fields: [{ source: "campusID", label: "Campus ID", required: true }], build: idParams },
      { label: "拒绝", action: "rejectCampusRequest", tone: "danger", visible: (r) => r.status === "pending", fields: [{ source: "note", label: "拒绝原因", kind: "longtext", required: true }], build: idParams },
    ],
  },
  posts: {
    label: "帖子",
    columns: columns(["title", "标题"], ["category", "分类"], ["status", "状态"], ["author.nickname", "作者"], ["like_count", "点赞", "number"], ["created_at", "发布时间", "date"]),
    statusChoices: status("published", "pending_review", "hidden", "deleted", "all"),
    exportable: true,
    actions: [
      { label: "下架", action: "moderatePost", tone: "danger", visible: (r) => r.status !== "hidden", fields: [reasonField("下架原因")], fixed: { status: "hidden" }, build: idParams },
      { label: "恢复", action: "moderatePost", visible: (r) => r.status === "hidden", fixed: { status: "published" }, build: idParams },
      { label: "全局置顶", action: "pinPost", visible: (r) => r.status === "published" && !r.pin, fields: [{ source: "priority", label: "优先级", kind: "number" }, { source: "startsAt", label: "开始时间", kind: "datetime" }, { source: "endsAt", label: "结束时间", kind: "datetime" }, reasonField("置顶原因")], fixed: { scope: "global" }, build: (r, v) => ({ postID: r.id, ...v }) },
      { label: "分类置顶", action: "pinPost", visible: (r) => r.status === "published" && !r.pin, fields: [{ source: "category", label: "分类", required: true }, { source: "priority", label: "优先级", kind: "number" }, { source: "startsAt", label: "开始时间", kind: "datetime" }, { source: "endsAt", label: "结束时间", kind: "datetime" }, reasonField("置顶原因")], fixed: { scope: "category" }, build: (r, v) => ({ postID: r.id, ...v }) },
      { label: "取消置顶", action: "unpinPost", tone: "danger", visible: (r) => Boolean(r.pin), build: (r) => ({ id: r.pin.id, postID: r.id }) },
    ],
  },
  polls: {
    label: "投票",
    columns: columns(["question", "问题"], ["status", "状态"], ["total_vote_count", "票数", "number"], ["closes_at", "截止", "date"], ["created_at", "创建", "date"]),
    statusChoices: status("published", "pending_review", "hidden", "deleted", "all"),
    exportable: true,
    actions: [
      { label: "下架", action: "moderatePoll", tone: "danger", fields: [reasonField()], fixed: { status: "hidden" }, build: idParams },
      { label: "恢复", action: "moderatePoll", visible: (r) => r.status === "hidden", fixed: { status: "published" }, build: idParams },
      { label: "批准删除", action: "reviewPollDeletion", tone: "danger", visible: (r) => r.deletion_status === "pending", fields: [reasonField()], fixed: { decision: "approved" }, build: idParams },
      { label: "拒绝删除", action: "reviewPollDeletion", visible: (r) => r.deletion_status === "pending", fields: [reasonField()], fixed: { decision: "rejected" }, build: idParams },
    ],
  },
  comments: {
    label: "评论",
    columns: columns(["body", "内容"], ["post.title", "帖子"], ["author.nickname", "作者"], ["status", "状态"], ["created_at", "时间", "date"]),
    statusChoices: status("published", "hidden", "deleted", "all"),
    exportable: true,
    actions: [
      { label: "下架", action: "moderateComment", tone: "danger", fields: [reasonField()], fixed: { status: "hidden" }, build: idParams },
      { label: "恢复", action: "moderateComment", visible: (r) => r.status === "hidden", fixed: { status: "published" }, build: idParams },
    ],
  },
  reports: {
    label: "举报",
    columns: columns(["target_type", "对象"], ["reason", "原因"], ["detail", "详情"], ["status", "状态"], ["created_at", "提交时间", "date"]),
    statusChoices: status("open", "reviewed", "resolved", "rejected", "all"),
    filters: [{ source: "targetType", label: "对象类型", kind: "select", choices: [{ id: "all", name: "全部" }, { id: "post", name: "帖子" }, { id: "comment", name: "评论" }, { id: "user", name: "用户" }] }],
    exportable: true,
    actions: [
      { label: "标记已看", action: "resolveModerationReport", fields: [{ source: "resolutionNote", label: "处理备注", kind: "longtext", required: true }], fixed: { status: "reviewed", hideContent: false }, build: idParams },
      { label: "下架并关闭", action: "resolveModerationReport", tone: "danger", fields: [{ source: "resolutionNote", label: "处理备注", kind: "longtext", required: true }], fixed: { status: "resolved", hideContent: true }, build: idParams },
      { label: "下架并禁言", action: "resolveModerationReport", tone: "danger", fields: [{ source: "resolutionNote", label: "处理备注", kind: "longtext", required: true }, { source: "mutedUntil", label: "禁言截止（留空默认一年）", kind: "datetime" }, { source: "mutedReason", label: "禁言原因", kind: "longtext" }], fixed: { status: "resolved", hideContent: true, muteUser: true }, build: idParams },
      { label: "驳回", action: "resolveModerationReport", fields: [{ source: "resolutionNote", label: "处理备注", kind: "longtext", required: true }], fixed: { status: "rejected", hideContent: false }, build: idParams },
    ],
  },
  profiles: {
    label: "用户",
    columns: columns(["nickname", "昵称"], ["display_name", "姓名"], ["edu_id", "学号"], ["community_access_status", "社区状态"], ["muted_until", "禁言截止", "date"], ["created_at", "创建", "date"]),
    exportable: true,
    filters: [{ source: "muted", label: "禁言状态", kind: "select", choices: [{ id: "all", name: "全部" }, { id: "active", name: "禁言中" }] }],
    actions: [
      { label: "禁言", action: "muteProfile", tone: "danger", fields: [{ source: "mutedUntil", label: "禁言截止", kind: "datetime", required: true }, reasonField("禁言原因")], build: idParams },
      { label: "解除禁言", action: "unmuteProfile", visible: (r) => Boolean(r.muted_until), build: idParams },
    ],
  },
  feedback: {
    label: "反馈",
    columns: columns(["issue_type", "类型", "text", true], ["body", "内容"], ["contact", "联系方式"], ["status", "状态", "text", true], ["created_at", "提交时间", "date", true]),
    statusChoices: feedbackStatus("open", "reviewed", "closed", "all"),
    editable: true, exportable: true,
    filters: [{ source: "issueType", label: "反馈类型" }],
    editForm: [{ source: "status", label: "状态", kind: "select", choices: feedbackStatus("open", "reviewed", "closed"), required: true }, { source: "adminNote", label: "处理备注", kind: "longtext" }],
    defaultSort: { field: "created_at", order: "DESC" },
  },
  announcements: {
    label: "公告",
    columns: columns(["title", "标题"], ["level", "级别"], ["status", "状态"], ["published_at", "发布时间", "date"], ["expires_at", "过期时间", "date"]),
    statusChoices: status("published", "draft", "archived", "all"), exportable: true, editable: true,
    ...forms([{ source: "title", label: "标题", required: true }, { source: "body", label: "正文", kind: "longtext", required: true }, { source: "level", label: "级别", kind: "select", choices: [{ id: "info", name: "普通" }, { id: "warning", name: "重要" }, { id: "urgent", name: "紧急" }] }, { source: "status", label: "状态", kind: "select", choices: status("published", "draft", "archived") }, { source: "publishedAt", label: "发布时间", kind: "datetime" }, { source: "expiresAt", label: "过期时间", kind: "datetime" }]),
  },
  postgraduate: {
    label: "考研信息",
    columns: columns(["title", "标题"], ["source_kind", "类型"], ["trust_level", "可信度"], ["school", "学校"], ["exam_year", "年份", "number"], ["status", "状态"]),
    statusChoices: status("published", "hidden", "archived", "all"), exportable: true, editable: true,
    filters: [{ source: "kind", label: "来源类型" }, { source: "trustLevel", label: "可信度" }],
    ...forms([{ source: "title", label: "标题", required: true }, { source: "summary", label: "摘要", kind: "longtext" }, { source: "sourceURL", label: "来源链接", required: true }, { source: "sourceKind", label: "类型", required: true }, { source: "trustLevel", label: "可信度", required: true }, { source: "school", label: "学校" }, { source: "unit", label: "单位" }, { source: "major", label: "专业" }, { source: "examYear", label: "年份", kind: "number" }, { source: "status", label: "状态", kind: "select", choices: status("published", "hidden", "archived") }]),
    actions: [
      { label: "隐藏", action: "setPostgraduateSourceStatus", tone: "danger", visible: (r) => r.status === "published", fixed: { status: "hidden" }, build: idParams },
      { label: "恢复", action: "setPostgraduateSourceStatus", visible: (r) => r.status !== "published", fixed: { status: "published" }, build: idParams },
      { label: "归档", action: "setPostgraduateSourceStatus", visible: (r) => r.status !== "archived", fixed: { status: "archived" }, build: idParams },
    ],
  },
  "postgraduate-suggestions": {
    label: "考研信息线索", columns: columns(["title", "标题"], ["source_kind", "类型"], ["school", "学校"], ["exam_year", "年份", "number"], ["status", "状态"], ["created_at", "提交时间", "date"]), statusChoices: status("open", "approved", "rejected", "all"),
    actions: [
      { label: "通过并入库", action: "approvePostgraduateSuggestion", fields: [{ source: "summary", label: "入库摘要", kind: "longtext" }, { source: "adminNote", label: "审核备注", kind: "longtext" }], build: idParams },
      { label: "驳回", action: "rejectPostgraduateSuggestion", tone: "danger", fields: [{ source: "adminNote", label: "驳回原因", kind: "longtext", required: true }], build: idParams },
    ],
    filters: [{ source: "kind", label: "来源类型" }],
  },
  suggestions: {
    label: "名录建议",
    columns: columns(["suggestion_type", "类型"], ["name", "名称"], ["unit", "单位"], ["category", "分类"], ["status", "状态"], ["created_at", "时间", "date"]),
    statusChoices: status("open", "approved", "rejected", "all"), exportable: true,
    filters: [{ source: "type", label: "建议类型", kind: "select", choices: [{ id: "all", name: "全部" }, { id: "teacher", name: "教师" }, { id: "course", name: "课程" }, { id: "dish", name: "菜品" }] }],
    actions: [
      { label: "通过", action: "approveCatalogSuggestion", fields: [{ source: "adminNote", label: "审核备注", kind: "longtext" }], build: idParams },
      { label: "驳回", action: "rejectCatalogSuggestion", tone: "danger", fields: [{ source: "adminNote", label: "驳回原因", kind: "longtext", required: true }], build: idParams },
    ],
  },
  teachers: catalog("教师", [["name", "姓名"], ["unit", "单位"], ["rating_average", "评分", "number"], ["rating_count", "人数", "number"], ["status", "状态"]], [{ source: "name", label: "姓名", required: true }, { source: "unit", label: "单位", required: true }, statusField()]),
  courses: { ...catalog("课程", [["name", "课程"], ["unit", "单位"], ["category", "分类"], ["credit", "学分", "number"], ["rating_average", "评分", "number"], ["status", "状态"]], [{ source: "name", label: "课程名", required: true }, { source: "unit", label: "单位", required: true }, { source: "category", label: "分类", required: true }, { source: "credit", label: "学分", kind: "number" }, statusField()]), filters: [{ source: "category", label: "课程分类" }] },
  dishes: { ...catalog("菜品", [["name", "菜名"], ["location", "地点"], ["rating_average", "评分", "number"], ["rating_count", "人数", "number"], ["status", "状态"]], [{ source: "name", label: "菜名", required: true }, { source: "location", label: "地点", required: true }, statusField()]), filters: [{ source: "location", label: "地点" }] },
  ratings: {
    label: "评分", columns: columns(["teacher.name", "教师"], ["dish.name", "菜品"], ["user.nickname", "用户"], ["stars", "星级", "number", true], ["updated_at", "时间", "date", true]), exportable: true, searchable: false,
    filters: [{ source: "teacherID", label: "教师 ID" }, { source: "dishID", label: "菜品 ID" }, { source: "userID", label: "用户 UUID" }, { source: "stars", label: "星级", kind: "select", choices: [1, 2, 3, 4, 5].map((id) => ({ id, name: `${id} 星` })) }],
    actions: [{ label: "删除", action: "__deleteRating", tone: "danger", permissionAction: "delete" }],
    defaultSort: { field: "updated_at", order: "DESC" },
  },
  admins: {
    label: "管理员", columns: columns(["username", "账号", "text", true], ["display_name", "显示名", "text", true], ["role", "角色", "text", true], ["active", "启用", "boolean", true], ["last_login_at", "上次登录", "date", true]), editable: true, exportable: true,
    createForm: [{ source: "username", label: "账号", required: true }, { source: "displayName", label: "显示名", required: true }, { source: "password", label: "密码", kind: "password", required: true }, { source: "role", label: "角色", kind: "select", choices: [{ id: "viewer", name: "只读" }, { id: "operator", name: "运营" }, { id: "super_admin", name: "超级管理员" }], required: true }, { source: "active", label: "启用", kind: "boolean" }],
    editForm: [{ source: "username", label: "账号", required: true }, { source: "displayName", label: "显示名", required: true }, { source: "password", label: "新密码（留空不修改）", kind: "password" }, { source: "role", label: "角色", kind: "select", choices: [{ id: "viewer", name: "只读" }, { id: "operator", name: "运营" }, { id: "super_admin", name: "超级管理员" }], required: true }, { source: "active", label: "启用", kind: "boolean" }],
    actions: [{ label: "停用", action: "disableAdmin", tone: "danger", permissionAction: "delete", visible: (r) => r.active === true, build: idParams }],
    defaultSort: { field: "created_at", order: "DESC" },
  },
  sessions: { label: "会话", columns: columns(["admin.display_name", "管理员"], ["is_current", "当前会话", "boolean"], ["last_seen_at", "最近活动", "date", true], ["expires_at", "过期", "date", true], ["revoked_at", "撤销", "date", true]), exportable: true, searchable: false, defaultSort: { field: "created_at", order: "DESC" }, filters: [{ source: "status", label: "状态", kind: "select", choices: [{ id: "all", name: "全部" }, { id: "active", name: "有效" }, { id: "revoked", name: "已撤销" }] }, { source: "adminID", label: "管理员 ID" }], actions: [{ label: "撤销", action: "revokeAdminSession", tone: "danger", permissionAction: "delete", visible: (r) => !r.revoked_at, build: idParams }] },
  "audit-logs": { label: "审计日志", columns: columns(["admin.display_name", "管理员"], ["action", "动作", "text", true], ["target_type", "对象", "text", true], ["outcome", "结果", "text", true], ["duration_ms", "耗时(ms)", "number", true], ["error_code", "错误码", "text", true], ["created_at", "时间", "date", true]), exportable: true, searchable: false, defaultSort: { field: "created_at", order: "DESC" }, filters: [{ source: "action", label: "动作" }, { source: "adminID", label: "管理员 ID" }] },
  "semester-configs": {
    label: "学期配置", columns: columns(["campus_id", "学校"], ["semester_id", "学期"], ["semester_start_date", "开始日期", "date"], ["supported_weeks", "周数", "number"], ["graduate_timetable_term_code", "研究生代码"], ["is_active", "启用", "boolean"]), editable: true,
    ...forms([{ source: "campusID", label: "Campus ID", required: true }, { source: "semesterID", label: "学期 ID", required: true }, { source: "semesterStartDate", label: "开始日期", kind: "date", required: true }, { source: "supportedWeeks", label: "周数", kind: "number", required: true }, { source: "graduateTimetableTermCode", label: "研究生学期代码", required: true }, { source: "calendarEvents", label: "校历事件 JSON", kind: "json", required: true }, { source: "isActive", label: "设为当前学期", kind: "boolean" }]), searchable: false,
  },
  "national-calendar": {
    label: "国家日历", columns: columns(["year", "年份", "number"], ["is_active", "启用", "boolean"], ["holidays", "节假日", "json"], ["solar_terms", "节气", "json"], ["updated_at", "更新", "date"]), editable: true,
    ...forms([{ source: "year", label: "年份", kind: "number", required: true }, { source: "holidays", label: "节假日 JSON", kind: "json", required: true }, { source: "solarTerms", label: "节气 JSON", kind: "json", required: true }, { source: "isActive", label: "设为当前", kind: "boolean" }]), searchable: false,
  },
};

function catalog(label: string, rawColumns: any[], form: FormFieldConfig[]): ResourceConfig {
  const entity = label === "教师" ? "Teacher" : label === "课程" ? "Course" : "Dish";
  return {
    label, columns: columns(...rawColumns.map(([source, columnLabel, kind = "text"]) => [source, columnLabel, kind, true])), createForm: form, editForm: form, editable: true, exportable: true,
    defaultSort: { field: "rating_average", order: "DESC" },
    statusChoices: status("published", "hidden", "all"),
    actions: [
      { label: "隐藏", action: `set${entity}Status`, tone: "danger", visible: (r) => r.status !== "hidden", fixed: { status: "hidden" }, build: idParams },
      { label: "恢复", action: `set${entity}Status`, visible: (r) => r.status === "hidden", fixed: { status: "published" }, build: idParams },
    ],
  };
}

function statusField(): FormFieldConfig { return { source: "status", label: "状态", kind: "select", choices: status("published", "hidden"), required: true }; }

function columns(...items: any[]): ColumnConfig[] {
  return items.map(([source, label, kind = "text", sortable = false]) => ({ source, label, kind, sortable }));
}

function forms(fields: FormFieldConfig[]) {
  return { createForm: fields, editForm: fields };
}

function statusName(value: string) {
  return ({ published: "已发布", pending: "待处理", pending_review: "待审核", hidden: "已隐藏", deleted: "已删除", open: "待处理", reviewed: "已查看", resolved: "已处理", rejected: "已驳回", closed: "已关闭", draft: "草稿", archived: "已下线", approved: "已通过", all: "全部" } as Record<string, string>)[value] ?? value;
}
