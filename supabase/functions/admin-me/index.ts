import {
  authenticateAdmin,
  json,
  mapFunctionError,
  okOptions,
} from "../_shared/admin-core.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return okOptions();
  }

  if (request.method !== "GET" && request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  try {
    const context = await authenticateAdmin(request);
    if (context instanceof Response) {
      return context;
    }

    return json({ admin: context.admin });
  } catch (error) {
    return mapFunctionError(error);
  }
});
