import {
  appendAuditLog,
  actionMeta,
  AdminContext,
  authenticateAdmin,
  databaseError,
  errorCodeFor,
  HttpError,
  json,
  mapFunctionError,
  requirePost,
} from "../_shared/admin-core.ts";

Deno.serve(async (request) => {
  const requestId = request.headers.get("x-request-id") || crypto.randomUUID();
  const methodResponse = requirePost(request);
  if (methodResponse) {
    return methodResponse;
  }

  let context: AdminContext | null = null;
  try {
    const authenticated = await authenticateAdmin(request);
    if (authenticated instanceof Response) {
      return authenticated;
    }
    context = authenticated;

    const { data, error } = await context.adminClient
      .from("admin_sessions")
      .update({ revoked_at: new Date().toISOString() })
      .eq("token_hash", context.tokenHash)
      .select("token_hash")
      .maybeSingle();
    if (error) throw databaseError(error);
    if (!data) throw new HttpError(404, "Admin session not found.");

    const auditLogged = await appendAuditLog(context, "logout", {});
    return json({ data: { ok: true }, meta: actionMeta(context, auditLogged) });
  } catch (error) {
    if (context) {
      await appendAuditLog(context, "logout", {}, undefined, {
        outcome: "failure",
        errorCode: errorCodeFor(error),
      });
    }
    return mapFunctionError(error, context?.requestId ?? requestId);
  }
});
