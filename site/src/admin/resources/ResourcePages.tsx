import { Fragment, useEffect, useMemo, useState } from "react";
import {
  BooleanField,
  Button,
  Create,
  CreateButton,
  Datagrid,
  DateField,
  FunctionField,
  FilterButton,
  List,
  NumberField,
  SelectInput,
  SimpleForm,
  TextField,
  TextInput,
  TopToolbar,
  useCanAccess,
  useDataProvider,
  useListContext,
  useNotify,
  useRecordContext,
  useRefresh,
} from "react-admin";
import type { RaRecord } from "react-admin";
import {
  Box,
  Card,
  CardContent,
  Checkbox,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControlLabel,
  MenuItem,
  Stack,
  TextField as MuiTextField,
  Typography,
} from "@mui/material";
import Download from "@mui/icons-material/Download";
import Edit from "@mui/icons-material/Edit";
import GppBad from "@mui/icons-material/GppBad";
import Visibility from "@mui/icons-material/Visibility";
import type { AdminDataProvider } from "../providers/dataProvider";
import type { ColumnConfig, FormFieldConfig, ResourceConfig, RowActionConfig } from "./config";
import { resourceConfigs } from "./config";

export function createResourcePages(resource: string) {
  const config = resourceConfigs[resource];
  if (!config) throw new Error(`Missing resource UI config for ${resource}`);
  return {
    list: () => <ResourceList resource={resource} config={config} />,
    create: config.createForm ? () => <ResourceCreate config={config} /> : undefined,
  };
}

export function ResourceList({ resource, config }: { resource: string; config: ResourceConfig }) {
  const filters = [
    ...(config.searchable === false ? [] : [<TextInput key="search" source="search" label="搜索" alwaysOn resettable />]),
    ...(config.statusChoices ? [<SelectInput key="status" source="status" label="状态" choices={config.statusChoices} alwaysOn />] : []),
    ...(resource === "ratings" ? [<SelectInput key="target" source="target" label="评分类型" choices={[{ id: "teacher", name: "教师" }, { id: "dish", name: "菜品" }]} alwaysOn />] : []),
    ...(config.filters ?? []).map(renderFilterInput),
    ...(dateFilterResources.has(resource) ? [
      <TextInput key="start" source="start" label="开始日期" type="date" />,
      <TextInput key="end" source="end" label="结束日期" type="date" />,
    ] : []),
  ];
  return (
    <><List
      title={config.label}
      filters={filters}
      perPage={20}
      pagination={<AdminPagination />}
      actions={<ListActions resource={resource} config={config} />}
      sort={config.defaultSort ?? { field: "created_at", order: "DESC" }}
    >
      <Datagrid bulkActionButtons={resource === "posts" || resource === "comments" ? <BulkHideButton resource={resource} /> : false} rowClick={false}>
        {config.columns.map(renderColumn)}
        <FunctionField label="操作" render={() => <RowActions resource={resource} config={config} />} />
      </Datagrid>
    </List>{resource === "posts" && <PostFeedPreview />}</>
  );
}

function PostFeedPreview() {
  const dataProvider = useDataProvider<AdminDataProvider>();
  const notify = useNotify();
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("");
  const [limit, setLimit] = useState(20);
  const [posts, setPosts] = useState<Record<string, any>[]>([]);
  const [loading, setLoading] = useState(false);

  async function load() {
    setLoading(true);
    try {
      const result = await dataProvider.execute<{ posts?: Record<string, any>[] }>("previewCommunityFeed", { search, category, limit });
      setPosts(result.posts ?? []);
    } catch (error) {
      notify(error instanceof Error ? error.message : "Feed 预览失败。", { type: "error" });
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); }, []);

  return (
    <Card sx={{ mt: 2 }}><CardContent>
      <Typography variant="h6" fontWeight={700}>客户端 Feed 预览</Typography>
      <Typography color="text.secondary" mb={2}>使用与客户端一致的排序结果核对全局/分类置顶。</Typography>
      <Stack direction={{ xs: "column", md: "row" }} spacing={1} mb={2}>
        <MuiTextField size="small" label="搜索" value={search} onChange={(event) => setSearch(event.target.value)} />
        <MuiTextField size="small" label="分类" value={category} onChange={(event) => setCategory(event.target.value)} />
        <MuiTextField size="small" select label="数量" value={limit} onChange={(event) => setLimit(Number(event.target.value))}>{[10, 20, 30, 50].map((value) => <MenuItem key={value} value={value}>{value}</MenuItem>)}</MuiTextField>
        <Button label={loading ? "加载中…" : "刷新预览"} disabled={loading} onClick={() => void load()} />
      </Stack>
      <Stack spacing={1}>{posts.length ? posts.map((post, index) => <Box key={post.id ?? index} sx={{ p: 1.5, border: "1px solid", borderColor: "divider", borderRadius: 1 }}><Stack direction="row" spacing={1}><Typography fontWeight={700}>#{index + 1} {post.title}</Typography>{post.pin && <Typography variant="caption" color="primary">{post.pin.scope === "category" ? "分类置顶" : "全局置顶"} · P{post.pin.priority ?? 0}</Typography>}</Stack><Typography variant="body2" color="text.secondary">{truncate(String(post.body ?? ""), 120)}</Typography></Box>) : <Typography color="text.secondary">暂无 Feed 结果。</Typography>}</Stack>
    </CardContent></Card>
  );
}

function renderFilterInput(field: FormFieldConfig) {
  if (field.kind === "select") return <SelectInput key={field.source} source={field.source} label={field.label} choices={field.choices ?? []} />;
  return <TextInput key={field.source} source={field.source} label={field.label} type={field.kind === "date" ? "date" : field.kind === "number" ? "number" : "text"} resettable />;
}

const dateFilterResources = new Set(["posts", "polls", "comments", "reports", "profiles", "feedback", "postgraduate-suggestions", "suggestions", "ratings", "audit-logs"]);

function renderColumn(config: ColumnConfig) {
  const props = { source: config.source, label: config.label, sortable: config.sortable === true };
  if (config.kind === "date") return <DateField key={config.source} {...props} showTime emptyText="—" />;
  if (config.kind === "number") return <NumberField key={config.source} {...props} emptyText="—" />;
  if (config.kind === "boolean") return <BooleanField key={config.source} {...props} />;
  if (config.kind === "json") return <FunctionField key={config.source} {...props} render={(record: RaRecord) => truncate(JSON.stringify(getValue(record, config.source)), 80)} />;
  return <FunctionField key={config.source} {...props} render={(record: RaRecord) => truncate(adminValueLabel(config.source, getValue(record, config.source)), config.source.includes("body") ? 120 : 60)} />;
}

function ListActions({ resource, config }: { resource: string; config: ResourceConfig }) {
  const { canAccess: canCreate } = useCanAccess({ resource, action: "create" });
  return (
    <TopToolbar>
      <FilterButton />
      {config.createForm && canCreate && <CreateButton />}
      {config.exportable && <ExportResourceButton resource={resource} />}
    </TopToolbar>
  );
}

function ExportResourceButton({ resource }: { resource: string }) {
  const dataProvider = useDataProvider<AdminDataProvider>();
  const notify = useNotify();
  const { filterValues, sort } = useListContext();
  const { canAccess } = useCanAccess({ resource, action: "export" });
  if (!canAccess) return null;
  return (
    <Button label="导出 CSV" startIcon={<Download />} onClick={async () => {
      try {
        await dataProvider.download({ resource, filters: filterValues, sort });
        notify("导出已生成。", { type: "success" });
      } catch (error) {
        notify(error instanceof Error ? error.message : "导出失败。", { type: "error" });
      }
    }} />
  );
}

function RowActions({ resource, config }: { resource: string; config: ResourceConfig }) {
  const record = useRecordContext<Record<string, any>>();
  if (!record) return null;
  return (
    <Stack direction="row" spacing={0.5} flexWrap="wrap">
      <RecordDetailDialog resource={resource} record={record} />
      {config.editable && config.editForm && <RecordFormDialog resource={resource} config={config} record={record} />}
      {config.actions?.filter((action) => !action.visible || action.visible(record)).map((action) => <ActionDialogButton key={action.label} resource={resource} record={record} action={action} />)}
    </Stack>
  );
}

function ActionDialogButton({ resource, record, action }: { resource: string; record: Record<string, any>; action: RowActionConfig }) {
  const dataProvider = useDataProvider<AdminDataProvider>();
  const notify = useNotify();
  const refresh = useRefresh();
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [values, setValues] = useState<Record<string, unknown>>({});
  const { canAccess } = useCanAccess({ resource, action: action.permissionAction ?? "edit", record });
  if (!canAccess) return null;

  async function run() {
    setLoading(true);
    try {
      if (action.action === "__deleteRating") {
        await dataProvider.delete(resource, { id: record.id, previousData: record as RaRecord });
      } else {
        const combined = { ...(action.fixed ?? {}), ...values };
        const payload = action.build ? action.build(record, combined) : { id: record.id, ...combined };
        await dataProvider.execute(action.action, payload);
      }
      notify(`${action.label}成功。`, { type: "success" });
      setOpen(false);
      refresh();
    } catch (error) {
      notify(error instanceof Error ? error.message : `${action.label}失败。`, { type: "error" });
    } finally {
      setLoading(false);
    }
  }

  const confirmation = actionConfirmation(resource, record, action);

  return (
    <>
      <Button color={action.tone === "danger" ? "error" : "primary"} label={action.label} onClick={() => setOpen(true)} />
      <Dialog open={open} onClose={() => !loading && setOpen(false)} fullWidth maxWidth="sm">
        <DialogTitle>{action.label}</DialogTitle>
        <DialogContent><Stack spacing={2} mt={1}><Typography fontWeight={650}>{confirmation.summary}</Typography><Typography color="text.secondary">{confirmation.impact} 操作结果将写入审计日志。</Typography>{action.fields?.map((field) => <DialogField key={field.source} field={field} value={values[field.source]} onChange={(value) => setValues((current) => ({ ...current, [field.source]: value }))} />)}{!action.fields?.length && <Typography>请确认继续执行。</Typography>}</Stack></DialogContent>
        <DialogActions><Button label="取消" onClick={() => setOpen(false)} /><Button label="确认" color={action.tone === "danger" ? "error" : "primary"} disabled={loading || action.fields?.some((field) => field.required && isMissing(values[field.source]))} onClick={() => void run()} /></DialogActions>
      </Dialog>
    </>
  );
}

function RecordFormDialog({ resource, config, record }: { resource: string; config: ResourceConfig; record: Record<string, any> }) {
  const dataProvider = useDataProvider<AdminDataProvider>();
  const notify = useNotify();
  const refresh = useRefresh();
  const [open, setOpen] = useState(false);
  const initial = useMemo(() => Object.fromEntries((config.editForm ?? []).map((field) => [field.source, formInitial(record, field)])), [config.editForm, record]);
  const [values, setValues] = useState<Record<string, unknown>>(initial);
  const [loading, setLoading] = useState(false);

  async function save() {
    setLoading(true);
    try {
      await dataProvider.update(resource, { id: record.id, data: values, previousData: record });
      notify("保存成功。", { type: "success" });
      setOpen(false);
      refresh();
    } catch (error) {
      notify(error instanceof Error ? error.message : "保存失败。", { type: "error" });
    } finally { setLoading(false); }
  }

  return (
    <>
      <Button label="编辑" startIcon={<Edit />} onClick={() => { setValues(initial); setOpen(true); }} />
      <Dialog open={open} onClose={() => !loading && setOpen(false)} fullWidth maxWidth="md">
        <DialogTitle>编辑{config.label}</DialogTitle>
        <DialogContent><Stack spacing={2} mt={1}>{config.editForm?.map((field) => <DialogField key={field.source} field={field} value={values[field.source]} onChange={(value) => setValues((current) => ({ ...current, [field.source]: value }))} />)}</Stack></DialogContent>
        <DialogActions><Button label="取消" onClick={() => setOpen(false)} /><Button label="保存" disabled={loading || config.editForm?.some((field) => field.required && isMissing(values[field.source]))} onClick={() => void save()} /></DialogActions>
      </Dialog>
    </>
  );
}

function ResourceCreate({ config }: { config: ResourceConfig }) {
  return (
    <Create title={`新增${config.label}`}>
      <SimpleForm>{config.createForm?.map((field) => <AdminInput key={field.source} field={field} />)}</SimpleForm>
    </Create>
  );
}

function AdminInput({ field }: { field: FormFieldConfig }) {
  const validate = field.required ? [(value: unknown) => value === undefined || value === null || value === "" ? "必填" : undefined] : undefined;
  if (field.kind === "select") return <SelectInput source={field.source} label={field.label} choices={field.choices ?? []} validate={validate} fullWidth />;
  if (field.kind === "boolean") return <SelectInput source={field.source} label={field.label} choices={[{ id: true, name: "是" }, { id: false, name: "否" }]} validate={validate} />;
  return <TextInput source={field.source} label={field.label} type={field.kind === "password" ? "password" : field.kind === "number" ? "number" : field.kind === "date" ? "date" : field.kind === "datetime" ? "datetime-local" : "text"} multiline={field.kind === "longtext" || field.kind === "json"} minRows={field.kind === "json" ? 8 : field.kind === "longtext" ? 4 : undefined} validate={validate} fullWidth />;
}

function DialogField({ field, value, onChange }: { field: FormFieldConfig; value: unknown; onChange: (value: unknown) => void }) {
  if (field.kind === "boolean") return <FormControlLabel control={<Checkbox checked={value === true} onChange={(event) => onChange(event.target.checked)} />} label={field.label} />;
  return (
    <MuiTextField
      label={field.label}
      value={value ?? ""}
      onChange={(event) => onChange(field.kind === "number" ? Number(event.target.value) : event.target.value)}
      select={field.kind === "select"}
      type={field.kind === "password" ? "password" : field.kind === "datetime" ? "datetime-local" : field.kind === "date" ? "date" : field.kind === "number" ? "number" : "text"}
      multiline={field.kind === "longtext" || field.kind === "json"}
      minRows={field.kind === "json" ? 8 : field.kind === "longtext" ? 3 : undefined}
      required={field.required}
      fullWidth
      InputLabelProps={field.kind === "date" || field.kind === "datetime" ? { shrink: true } : undefined}
    >
      {field.choices?.map((choice) => <MenuItem key={choice.id} value={choice.id}>{choice.name}</MenuItem>)}
    </MuiTextField>
  );
}

function BulkHideButton({ resource }: { resource: string }) {
  const { selectedIds, onUnselectItems } = useListContext();
  const dataProvider = useDataProvider<AdminDataProvider>();
  const notify = useNotify();
  const refresh = useRefresh();
  const [mode, setMode] = useState<"hidden" | "published" | null>(null);
  const [reason, setReason] = useState("违反社区规范");
  const action = resource === "posts" ? "bulkModeratePosts" : "bulkModerateComments";
  return (
    <>
      <Button label="批量下架" color="error" startIcon={<GppBad />} onClick={() => setMode("hidden")} />
      <Button label="批量恢复" onClick={() => setMode("published")} />
      <Dialog open={mode !== null} onClose={() => setMode(null)}><DialogTitle>{mode === "hidden" ? "批量下架" : "批量恢复"} {selectedIds.length} 条记录</DialogTitle><DialogContent><Typography color="text.secondary" sx={{ mt: 1, mb: mode === "hidden" ? 2 : 0 }}>该操作不会乐观更新；后端确认成功后才刷新列表，并写入审计日志。</Typography>{mode === "hidden" && <MuiTextField label="下架原因" value={reason} onChange={(event) => setReason(event.target.value)} fullWidth multiline minRows={3} />}</DialogContent><DialogActions><Button label="取消" onClick={() => setMode(null)} /><Button label={mode === "hidden" ? "确认下架" : "确认恢复"} color={mode === "hidden" ? "error" : "primary"} disabled={mode === "hidden" && !reason.trim()} onClick={async () => { try { await dataProvider.execute(action, { ids: selectedIds, status: mode, ...(mode === "hidden" ? { reason } : {}) }); notify(mode === "hidden" ? "批量下架成功。" : "批量恢复成功。", { type: "success" }); onUnselectItems(); setMode(null); refresh(); } catch (error) { notify(error instanceof Error ? error.message : "批量操作失败。", { type: "error" }); } }} /></DialogActions></Dialog>
    </>
  );
}

function RecordDetailDialog({ resource, record }: { resource: string; record: Record<string, any> }) {
  const dataProvider = useDataProvider<AdminDataProvider>();
  const notify = useNotify();
  const { canAccess } = useCanAccess({ resource, action: "show", record });
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [detail, setDetail] = useState<Record<string, any>>(record);
  if (!canAccess) return null;

  async function show() {
    setOpen(true);
    setDetail(record);
    if (!detailResources.has(resource)) return;
    setLoading(true);
    try {
      const result = await dataProvider.getOne(resource, { id: record.id });
      setDetail(result.data as Record<string, any>);
    } catch (error) {
      notify(error instanceof Error ? error.message : "详情加载失败。", { type: "error" });
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <Button label="查看" startIcon={<Visibility />} onClick={() => void show()} />
      <Dialog open={open} onClose={() => setOpen(false)} fullWidth maxWidth="md">
        <DialogTitle>记录详情</DialogTitle>
        <DialogContent>
          {loading ? <Typography color="text.secondary">正在加载完整详情…</Typography> : <Box component="pre" sx={{ m: 0, p: 2, bgcolor: "grey.50", borderRadius: 1, overflow: "auto", whiteSpace: "pre-wrap", wordBreak: "break-word", fontSize: 13 }}>{JSON.stringify(detail, null, 2)}</Box>}
        </DialogContent>
        <DialogActions><Button label="关闭" onClick={() => setOpen(false)} /></DialogActions>
      </Dialog>
    </>
  );
}

const detailResources = new Set(["posts", "polls", "profiles"]);

function AdminPagination() {
  const { page, perPage, setPage, setPerPage, total = 0 } = useListContext();
  const pages = Math.max(1, Math.ceil(total / perPage));
  return <Stack direction="row" justifyContent="flex-end" alignItems="center" spacing={2} p={2}><Typography variant="body2">共 {total} 条</Typography><MuiTextField select size="small" value={perPage} onChange={(event) => setPerPage(Number(event.target.value))}>{[20, 50, 100].map((size) => <MenuItem key={size} value={size}>{size} 条/页</MenuItem>)}</MuiTextField><Button label="上一页" disabled={page <= 1} onClick={() => setPage(page - 1)} /><Typography>{page}/{pages}</Typography><Button label="下一页" disabled={page >= pages} onClick={() => setPage(page + 1)} /></Stack>;
}

function getValue(record: Record<string, any>, source: string) { return source.split(".").reduce((value, key) => value?.[key], record); }
function truncate(value: string, max: number) { return value.length > max ? `${value.slice(0, max - 1)}…` : value; }
function adminValueLabel(source: string, value: unknown) {
  if (value === undefined || value === null || value === "") return "—";
  const labels: Record<string, string> = {
    published: "已发布", pending: "待处理", pending_review: "待审核", hidden: "已隐藏", deleted: "已删除",
    open: "未查看", reviewed: "已查看待处理", resolved: "已处理", rejected: "已驳回", closed: "已完成",
    draft: "草稿", archived: "已下线", approved: "已通过", success: "成功", failure: "失败",
    viewer: "只读管理员", operator: "运营管理员", super_admin: "超级管理员",
  };
  const text = String(value);
  return source === "status" || source.endsWith("_status") || source === "outcome" || source === "role"
    ? labels[text] ?? text
    : text;
}

function actionConfirmation(resource: string, record: Record<string, any>, action: RowActionConfig) {
  if (resource === "ratings") {
    const target = record.teacher?.name ?? record.dish?.name ?? `ID ${record.teacher_id ?? record.dish_id}`;
    const user = record.user?.nickname ?? record.user_id ?? "未知用户";
    const time = record.updated_at ? new Date(record.updated_at).toLocaleString("zh-CN") : "时间未知";
    return {
      summary: `删除 ${target} 的 ${record.stars ?? "—"} 星评分（用户：${user}，${time}）`,
      impact: "删除后无法恢复，相关聚合评分会立即重新计算。",
    };
  }
  if (resource === "sessions") {
    const admin = record.admin?.display_name ?? record.admin_id ?? "未知管理员";
    const lastSeen = record.last_seen_at ? new Date(record.last_seen_at).toLocaleString("zh-CN") : "无活动记录";
    return { summary: `撤销 ${admin} 的管理会话（最近活动：${lastSeen}）`, impact: "该会话会立即失效，管理员需要重新登录。" };
  }
  if (resource === "admins" && action.action === "disableAdmin") {
    const admin = record.display_name ?? record.username ?? record.id;
    return { summary: `停用管理员账号：${admin}`, impact: "账号将无法继续登录，已有会话也应尽快撤销。" };
  }
  const identity = record.title ?? record.name ?? record.nickname ?? record.display_name ?? record.id ?? "当前记录";
  return { summary: `${action.label}：${identity}`, impact: "此操作会立即影响当前记录。" };
}
function isMissing(value: unknown) { return value === undefined || value === null || (typeof value === "string" && value.trim() === ""); }
function toSnake(value: string) {
  return value
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
    .toLowerCase();
}
function formInitial(record: Record<string, any>, field: FormFieldConfig) {
  const value = record[field.source] ?? record[toSnake(field.source)] ?? (field.source === "adminNote" ? record.admin_note : undefined);
  if (field.kind === "json" && value && typeof value !== "string") return JSON.stringify(value, null, 2);
  if (field.kind === "datetime" && typeof value === "string") return value.slice(0, 16);
  return value ?? (field.kind === "boolean" ? false : "");
}
