import {
  appendAuditLog,
  authenticateAdmin,
  json,
  mapFunctionError,
  requirePost,
} from "../_shared/admin-core.ts";

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

    await appendAuditLog(context, "logout", {});
    await context.adminClient
      .from("admin_sessions")
      .update({ revoked_at: new Date().toISOString() })
      .eq("token_hash", context.tokenHash);

    return json({ ok: true });
  } catch (error) {
    return mapFunctionError(error);
  }
});
