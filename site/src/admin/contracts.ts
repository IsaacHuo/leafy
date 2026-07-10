export type AdminRole = "super_admin" | "operator" | "viewer";

// admin-community action metadata uses the minimum permitted role as its permission value.
export type AdminPermission = AdminRole;

export type ApiMetadata = {
  request_id?: string;
  audit_logged?: boolean;
  duration_ms?: number;
};

export type ApiResponse<T> = {
  data: T;
  meta?: ApiMetadata;
};

export type StructuredApiError = {
  code: string;
  message: string;
  status: number;
  details?: Record<string, unknown>;
  field_errors?: Record<string, readonly string[]>;
  request_id?: string;
};

export type ApiErrorResponse = {
  error: StructuredApiError;
};

export type GlobalSearchRequest = {
  query: string;
  resources?: readonly string[];
  limit?: number;
};

export type GlobalSearchResult = {
  resource: string;
  id: string | number;
  label: string;
  description?: string;
  href?: string;
  metadata?: Record<string, unknown>;
};

export type GlobalSearchResponse = ApiResponse<readonly GlobalSearchResult[]>;

export type ExportFormat = "csv";

export type ExportRequest = {
  resource: string;
  format: ExportFormat;
  filters?: Record<string, unknown>;
  sort?: {
    field: string;
    order: "ASC" | "DESC";
  };
  fields?: readonly string[];
  ids?: readonly (string | number)[];
};
