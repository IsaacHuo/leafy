import { useEffect } from "react";
import { Admin, Resource } from "react-admin";
import { BrowserRouter } from "react-router-dom";
import { createTheme } from "@mui/material/styles";
import { AdminLogin } from "./components/AdminLogin";
import { AdminLayout } from "./components/AdminLayout";
import { AdminDashboard } from "./dashboard/Dashboard";
import { authProvider } from "./providers/authProvider";
import { dataProvider } from "./providers/dataProvider";
import { purgeLegacyAdminSession } from "./providers/session";
import { CampusesPage, ManualPage, PostgraduatePage } from "./resources/CompositePages";
import { createResourcePages } from "./resources/ResourcePages";
import { resourceConfigs } from "./resources/config";
import "./admin.css";

const theme = createTheme({
  palette: {
    mode: "light",
    primary: { main: "#249361", light: "#3ecf8e", dark: "#176a45" },
    secondary: { main: "#3ecf8e", dark: "#249361" },
    background: { default: "#f7f9f8", paper: "#ffffff" },
    error: { main: "#c62828" },
  },
  shape: { borderRadius: 8 },
  typography: {
    fontFamily: 'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    h3: { fontSize: "2rem" },
    h4: { fontSize: "1.55rem" },
  },
  components: {
    MuiButton: { defaultProps: { disableElevation: true }, styleOverrides: { root: { textTransform: "none", fontWeight: 650 } } },
    MuiCard: { styleOverrides: { root: { border: "1px solid #e4e9e6", boxShadow: "0 1px 2px rgba(0,0,0,.035)" } } },
    MuiTableCell: { styleOverrides: { root: { paddingTop: 10, paddingBottom: 10 } } },
  },
});

export const i18nProvider = {
  translate: (key: string, options: Record<string, unknown> = {}) => translateMessage(String(chineseMessages[key] ?? options._ ?? key), options),
  changeLocale: async () => undefined,
  getLocale: () => "zh-CN",
};

const chineseMessages: Record<string, string> = {
  "ra.action.add_filter": "添加筛选",
  "ra.action.back": "返回",
  "ra.action.bulk_actions": "已选择 1 项 |||| 已选择 %{smart_count} 项",
  "ra.action.close": "关闭",
  "ra.action.confirm": "确认",
  "ra.action.create": "新增",
  "ra.action.create_item": "新增%{item}",
  "ra.action.edit": "编辑",
  "ra.action.export": "导出",
  "ra.action.list": "列表",
  "ra.action.open_menu": "展开菜单",
  "ra.action.close_menu": "收起菜单",
  "ra.action.remove_filter": "移除筛选",
  "ra.action.reset": "重置",
  "ra.action.save": "保存",
  "ra.action.delete": "删除",
  "ra.action.show": "查看",
  "ra.action.search": "搜索",
  "ra.action.sort": "排序",
  "ra.action.refresh": "刷新",
  "ra.action.cancel": "取消",
  "ra.action.select_all": "全选",
  "ra.action.select_row": "选择此行",
  "ra.action.unselect": "取消选择",
  "ra.boolean.true": "是",
  "ra.boolean.false": "否",
  "ra.page.dashboard": "总览",
  "ra.page.error": "页面发生错误",
  "ra.page.not_found": "页面不存在",
  "ra.page.access_denied": "无权访问",
  "ra.message.access_denied": "当前账号没有访问此页面的权限。",
  "ra.message.are_you_sure": "确定继续吗？",
  "ra.message.error": "请求未能完成，请查看错误信息后重试。",
  "ra.message.invalid_form": "表单校验未通过，请检查输入。",
  "ra.message.not_found": "地址不正确，或目标资源已不存在。",
  "ra.navigation.clear_filters": "清除筛选",
  "ra.navigation.next": "下一页",
  "ra.navigation.previous": "上一页",
  "ra.auth.sign_out": "退出登录",
  "ra.auth.logout": "退出登录",
  "ra.auth.user_menu": "账号菜单",
  "ra.auth.auth_check_error": "请登录后继续",
  "ra.navigation.no_results": "暂无数据",
  "ra.navigation.no_filtered_results": "当前筛选下暂无%{name}",
  "ra.navigation.page_rows_per_page": "每页行数：",
  "ra.navigation.page_range_info": "%{offsetBegin}-%{offsetEnd} / %{total}",
  "ra.navigation.skip_nav": "跳到主要内容",
  "ra.sort.sort_by": "按%{field}排序（%{order}）",
  "ra.sort.ASC": "升序",
  "ra.sort.DESC": "降序",
  "ra.page.loading": "加载中",
  "ra.notification.updated": "保存成功",
  "ra.notification.created": "创建成功",
  "ra.notification.deleted": "删除成功",
  "ra.notification.http_error": "后台服务通信失败",
  "ra.notification.logged_out": "会话已结束，请重新登录。",
  "ra.notification.not_authorized": "当前账号无权执行此操作。",
  "ra.validation.required": "必填",
};

function translateMessage(template: string, options: Record<string, unknown>) {
  const variants = template.split("||||");
  const selected = variants.length > 1 && Number(options.smart_count ?? 1) !== 1 ? variants[1] : variants[0];
  return selected.trim().replace(/%\{([^}]+)\}/g, (_, key) => String(options[key] ?? ""));
}

const regularResources = [
  "posts", "polls", "comments", "reports", "profiles", "feedback", "announcements",
  "suggestions", "teachers", "courses", "dishes", "ratings", "semester-configs",
  "national-calendar", "admins", "sessions", "audit-logs",
] as const;

export default function AdminConsole() {
  useEffect(() => {
    purgeLegacyAdminSession();
    document.body.classList.add("leafy-admin-active");
    return () => document.body.classList.remove("leafy-admin-active");
  }, []);

  return (
    <BrowserRouter basename="/admin">
      <Admin
      dashboard={AdminDashboard}
      loginPage={AdminLogin}
      layout={AdminLayout}
      authProvider={authProvider}
      dataProvider={dataProvider}
      i18nProvider={i18nProvider}
      theme={theme}
      requireAuth
      disableTelemetry
      title="MyLeafy 管理后台"
    >
      <Resource name="manual" list={ManualPage} options={{ label: "手册" }} />
      <Resource name="campuses" list={CampusesPage} options={{ label: "学校" }} />
      <Resource name="campus-requests" options={{ label: "学校归属申请" }} />
      <Resource name="postgraduate" list={PostgraduatePage} create={createResourcePages("postgraduate").create} options={{ label: "考研信息" }} />
      <Resource name="postgraduate-suggestions" options={{ label: "考研线索" }} />
      {regularResources.map((resource) => {
        const pages = createResourcePages(resource);
        return <Resource key={resource} name={resource} list={pages.list} create={pages.create} options={{ label: resourceConfigs[resource].label }} />;
      })}
      </Admin>
    </BrowserRouter>
  );
}
