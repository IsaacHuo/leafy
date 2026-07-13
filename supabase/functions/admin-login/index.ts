import {
  appendAuditLog,
  createAdminClient,
  errorResponse,
  json,
  mapFunctionError,
  normalizeText,
  okOptions,
  readJSON,
} from "../_shared/admin-core.ts";
import { permissionsForRole } from "../_shared/admin-permissions.ts";

type LoginRequest = {
  username?: string | null;
  password?: string | null;
};

Deno.serve(async (request) => {
  const startedAt = Date.now();
  const requestId = request.headers.get("x-request-id") || crypto.randomUUID();
  if (request.method === "OPTIONS") {
    return okOptions();
  }

  if (request.method !== "POST") {
    return errorResponse(405, "method_not_allowed", "Method not allowed.", { retryable: false });
  }

  const expectedProxySecret = Deno.env.get("ADMIN_PROXY_SECRET");
  if (!expectedProxySecret || request.headers.get("x-leafy-admin-proxy") !== expectedProxySecret) {
    return errorResponse(403, "forbidden", "Admin login must use the same-origin proxy.");
  }

  try {
    const body = await readJSON<LoginRequest>(request);
    const username = normalizeText(body.username);
    const password = typeof body.password === "string" ? body.password : "";

    if (!username || !password) {
      return errorResponse(400, "bad_request", "账号和密码不能为空。");
    }

    const adminClient = createAdminClient();
    const ipAddress = clientIPAddress(request);
    const { data: attemptRows, error: attemptBeginError } = await adminClient.rpc("admin_begin_login_attempt", {
      p_username: username,
      p_ip_address: ipAddress,
    });
    if (attemptBeginError) {
      console.error(JSON.stringify({ event: "admin_login_attempt_start_failed", request_id: requestId, error: attemptBeginError.message }));
      return errorResponse(500, "backend_unavailable", "后台暂时不可用，请稍后重试。", { details: { request_id: requestId } });
    }
    const attempt = Array.isArray(attemptRows) ? attemptRows[0] : attemptRows;
    if (attempt?.is_rate_limited) {
      return errorResponse(429, "rate_limited", "登录尝试过于频繁，请稍后再试。", {
        retryable: true,
        details: { retry_after: attempt.retry_after, request_id: requestId },
      });
    }
    if (!attempt?.attempt_id) {
      return errorResponse(500, "backend_unavailable", "Unable to register admin login attempt.");
    }

    const { data, error } = await adminClient.rpc("admin_login", {
      p_username: username,
      p_password: password,
      p_expires_in_hours: 12,
    });

    if (error) {
      const invalidCredentials = error.message.includes("ADMIN_INVALID_CREDENTIALS");
      const { error: attemptError } = await adminClient.rpc("admin_finish_login_attempt", {
        p_attempt_id: attempt.attempt_id,
        p_succeeded: false,
        p_error_code: invalidCredentials ? "invalid_credentials" : "backend_error",
      });
      if (attemptError) {
        console.error(JSON.stringify({ event: "admin_login_attempt_audit_failed", request_id: requestId, error: attemptError.message }));
      }
      if (!invalidCredentials) {
        console.error(JSON.stringify({ event: "admin_login_failed", request_id: requestId, error: error.message }));
      }
      const message = invalidCredentials ? "账号或密码错误。" : "后台暂时不可用，请稍后重试。";
      return errorResponse(
        error.message.includes("ADMIN_INVALID_CREDENTIALS") ? 401 : 500,
        error.message.includes("ADMIN_INVALID_CREDENTIALS") ? "unauthorized" : "backend_unavailable",
        message,
      );
    }

    const row = Array.isArray(data) ? data[0] : data;
    if (!row?.token) {
      await adminClient.rpc("admin_finish_login_attempt", {
        p_attempt_id: attempt.attempt_id,
        p_succeeded: false,
        p_error_code: "invalid_credentials",
      });
      return errorResponse(401, "unauthorized", "账号或密码错误。");
    }

    const { error: attemptError } = await adminClient.rpc("admin_finish_login_attempt", {
      p_attempt_id: attempt.attempt_id,
      p_succeeded: true,
      p_error_code: null,
    });
    if (attemptError) {
      console.error(JSON.stringify({ event: "admin_login_attempt_audit_failed", request_id: requestId, error: attemptError.message }));
    }

    const requestInfo = {
      ipAddress,
      userAgent: request.headers.get("user-agent"),
    };

    await appendAuditLog({
      adminClient,
      admin: {
        id: row.admin_id,
        username: row.username,
        display_name: row.display_name,
        role: row.role,
        active: true,
      },
      tokenHash: "",
      sessionExpiresAt: row.expires_at,
      requestId,
      startedAt,
      requestInfo,
    }, "login", { username });

    return json({
      token: row.token,
      expires_at: row.expires_at,
      admin: {
        id: row.admin_id,
        username: row.username,
        display_name: row.display_name,
        role: row.role,
      },
      permissions: permissionsForRole(row.role),
      session: { expires_at: row.expires_at },
    });
  } catch (error) {
    return mapFunctionError(error, requestId);
  }
});

function clientIPAddress(request: Request) {
  return request.headers.get("x-leafy-client-ip")
    || request.headers.get("cf-connecting-ip")
    || request.headers.get("x-real-ip")
    || request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || "0.0.0.0";
}
