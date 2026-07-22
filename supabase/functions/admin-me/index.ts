import {
  authenticateAdmin,
  errorResponse,
  json,
  mapFunctionError,
  okOptions,
} from "../_shared/admin-core.ts";
import { permissionsForRole } from "../_shared/admin-permissions.ts";

Deno.serve(async (request) => {
  const requestId = request.headers.get("x-request-id") || crypto.randomUUID();
  if (request.method === "OPTIONS") {
    return okOptions();
  }

  if (request.method !== "GET" && request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Method not allowed.", { retryable: false });
  }

  try {
    const context = await authenticateAdmin(request);
    if (context instanceof Response) {
      return context;
    }

    return json({
      admin: context.admin,
      permissions: permissionsForRole(context.admin.role),
      session: { expires_at: context.sessionExpiresAt },
    });
  } catch (error) {
    return mapFunctionError(error, requestId);
  }
});
