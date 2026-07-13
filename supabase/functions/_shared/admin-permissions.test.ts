import { assertEquals } from "jsr:@std/assert@1";
import { permissionsForRole, roleCanExport } from "./admin-permissions.ts";

Deno.test("viewer permissions are read-only and cannot export", () => {
  const permissions = permissionsForRole("viewer");
  assertEquals(permissions.find((item) => item.resource === "posts")?.actions, ["list", "show"]);
  assertEquals(permissions.find((item) => item.resource === "campus-requests")?.actions, ["list", "show"]);
  assertEquals(roleCanExport("viewer", "posts"), false);
});

Deno.test("operator can export operational data but not sensitive resources", () => {
  const permissions = permissionsForRole("operator");
  assertEquals(roleCanExport("operator", "posts"), true);
  assertEquals(roleCanExport("operator", "profiles"), false);
  assertEquals(roleCanExport("operator", "feedback"), false);
  assertEquals(permissions.find((item) => item.resource === "feedback")?.actions.includes("create"), false);
  assertEquals(permissions.find((item) => item.resource === "ratings")?.actions.includes("delete"), true);
});

Deno.test("super admin receives system permissions and sensitive export", () => {
  const permissions = permissionsForRole("super_admin");
  assertEquals(permissions.some((item) => item.resource === "sessions" && item.actions.includes("delete")), true);
  assertEquals(roleCanExport("super_admin", "feedback"), true);
});
