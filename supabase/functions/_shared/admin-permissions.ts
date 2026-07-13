import type { AdminRole } from "./admin-core.ts";

export type AdminPermission = {
  resource: string;
  actions: string[];
};

const readableResources = [
  "dashboard",
  "manual",
  "campuses",
  "campus-requests",
  "posts",
  "polls",
  "comments",
  "reports",
  "profiles",
  "feedback",
  "announcements",
  "postgraduate",
  "postgraduate-suggestions",
  "suggestions",
  "teachers",
  "courses",
  "dishes",
  "ratings",
  "semester-configs",
  "national-calendar",
] as const;

const operatorExportResources = new Set([
  "posts",
  "polls",
  "comments",
  "reports",
  "announcements",
  "postgraduate",
  "suggestions",
  "teachers",
  "courses",
  "dishes",
  "ratings",
]);

const operatorResourceActions: Record<string, string[]> = {
  "campus-requests": ["edit"],
  posts: ["edit", "bulk", "export"],
  polls: ["edit", "export"],
  comments: ["edit", "bulk", "export"],
  reports: ["edit", "export"],
  profiles: ["edit"],
  feedback: ["edit"],
  announcements: ["create", "edit", "export"],
  postgraduate: ["create", "edit", "export"],
  "postgraduate-suggestions": ["edit"],
  suggestions: ["edit", "export"],
  teachers: ["create", "edit", "export"],
  courses: ["create", "edit", "export"],
  dishes: ["create", "edit", "export"],
  ratings: ["delete", "export"],
  "semester-configs": ["create", "edit"],
  "national-calendar": ["create", "edit"],
};

export function permissionsForRole(role: AdminRole): AdminPermission[] {
  const permissions: AdminPermission[] = readableResources.map((resource) => ({
    resource,
    actions: role === "viewer"
      ? ["list", "show"]
      : ["list", "show", ...(operatorResourceActions[resource] ?? [])],
  }));

  permissions.push({ resource: "global-search", actions: ["search"] });

  if (role === "super_admin") {
    permissions.push(
      { resource: "profiles", actions: ["list", "show", "edit", "bulk", "export"] },
      { resource: "feedback", actions: ["list", "show", "edit", "bulk", "export"] },
      { resource: "admins", actions: ["list", "show", "create", "edit", "delete", "export"] },
      { resource: "sessions", actions: ["list", "show", "delete", "export"] },
      { resource: "audit-logs", actions: ["list", "show", "export"] },
    );
  }

  return mergePermissions(permissions);
}

export function roleCanExport(role: AdminRole, resource: string): boolean {
  if (role === "viewer") return false;
  if (operatorExportResources.has(resource)) return true;
  return role === "super_admin" && ["profiles", "feedback", "admins", "sessions", "audit-logs"].includes(resource);
}

function mergePermissions(permissions: AdminPermission[]): AdminPermission[] {
  const merged = new Map<string, Set<string>>();
  for (const permission of permissions) {
    const actions = merged.get(permission.resource) ?? new Set<string>();
    permission.actions.forEach((action) => actions.add(action));
    merged.set(permission.resource, actions);
  }
  return Array.from(merged, ([resource, actions]) => ({ resource, actions: Array.from(actions) }));
}
