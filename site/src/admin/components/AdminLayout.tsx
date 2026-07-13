import { useEffect, useMemo, useRef, useState } from "react";
import {
  AppBar,
  Layout,
  Menu,
  TitlePortal,
  useDataProvider,
  useCanAccess,
  useRedirect,
  useRefresh,
  useNotify,
} from "react-admin";
import type { LayoutProps } from "react-admin";
import {
  Autocomplete,
  Box,
  MenuItem,
  Select,
  Stack,
  TextField,
  Typography,
} from "@mui/material";
import AccountCircle from "@mui/icons-material/AccountCircle";
import Apartment from "@mui/icons-material/Apartment";
import Assessment from "@mui/icons-material/Assessment";
import Campaign from "@mui/icons-material/Campaign";
import Chat from "@mui/icons-material/Chat";
import Comment from "@mui/icons-material/Comment";
import Dashboard from "@mui/icons-material/Dashboard";
import Event from "@mui/icons-material/Event";
import FactCheck from "@mui/icons-material/FactCheck";
import Flag from "@mui/icons-material/Flag";
import FoodBank from "@mui/icons-material/FoodBank";
import History from "@mui/icons-material/History";
import HowToReg from "@mui/icons-material/HowToReg";
import LibraryBooks from "@mui/icons-material/LibraryBooks";
import ManageAccounts from "@mui/icons-material/ManageAccounts";
import MenuBook from "@mui/icons-material/MenuBook";
import Poll from "@mui/icons-material/Poll";
import RateReview from "@mui/icons-material/RateReview";
import School from "@mui/icons-material/School";
import Search from "@mui/icons-material/Search";
import Settings from "@mui/icons-material/Settings";
import Star from "@mui/icons-material/Star";
import type { AdminDataProvider } from "../providers/dataProvider";
import type { GlobalSearchResult } from "../contracts";
import { readCampusScope, saveCampusScope } from "../providers/session";

type Campus = { id: string; display_name: string };

export function AdminLayout(props: LayoutProps) {
  return <Layout {...props} appBar={AdminAppBar} menu={AdminMenu} />;
}

function AdminAppBar() {
  const dataProvider = useDataProvider<AdminDataProvider>();
  const redirect = useRedirect();
  const refresh = useRefresh();
  const notify = useNotify();
  const [campusID, setCampusID] = useState(readCampusScope());
  const [campuses, setCampuses] = useState<Campus[]>([]);
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<GlobalSearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const searchSequence = useRef(0);

  useEffect(() => {
    const showAuditWarning = (event: Event) => {
      const detail = (event as CustomEvent<{ action?: string; requestID?: string }>).detail;
      notify(`操作已完成，但审计写入失败${detail?.requestID ? `（请求 ID: ${detail.requestID}）` : ""}。`, { type: "warning" });
    };
    window.addEventListener("leafy-admin-audit-warning", showAuditWarning);
    return () => window.removeEventListener("leafy-admin-audit-warning", showAuditWarning);
  }, [notify]);

  useEffect(() => {
    dataProvider.execute<{ items: Campus[] }>("listCampuses", { status: "all", page: 0, pageSize: 100 })
      .then((data) => setCampuses(data.items))
      .catch((error) => {
        setCampuses([]);
        notify(error instanceof Error ? error.message : "学校范围加载失败。", { type: "error" });
      });
  }, [dataProvider, notify]);

  useEffect(() => {
    const sequence = ++searchSequence.current;
    if (query.trim().length < 2) {
      setResults([]);
      setSearching(false);
      return;
    }
    const timer = window.setTimeout(() => {
      setSearching(true);
      dataProvider.globalSearch(query.trim()).then((nextResults) => {
        if (sequence === searchSequence.current) setResults(nextResults);
      }).catch((error) => {
        if (sequence !== searchSequence.current) return;
        setResults([]);
        notify(error instanceof Error ? error.message : "全局搜索失败。", { type: "error" });
      }).finally(() => {
        if (sequence === searchSequence.current) setSearching(false);
      });
    }, 250);
    return () => window.clearTimeout(timer);
  }, [dataProvider, notify, query]);

  const options = useMemo(() => results.map((result) => ({ ...result, label: result.title })), [results]);

  return (
    <AppBar color="inherit" elevation={0} sx={{ borderBottom: "1px solid", borderColor: "divider" }}>
      <Stack direction="row" spacing={2} alignItems="center" width="100%">
        <Typography variant="h6" fontWeight={800} color="primary.main" whiteSpace="nowrap" sx={{ display: { xs: "none", md: "block" } }}>MyLeafy Admin</Typography>
        <TitlePortal />
        <Box flex={1} />
        <Autocomplete
          size="small"
          sx={{ width: { xs: 160, md: 240, lg: 360 } }}
          options={options}
          loading={searching}
          loadingText="正在搜索…"
          noOptionsText={query.trim().length < 2 ? "请输入至少 2 个字符" : "未找到匹配结果"}
          openText="打开搜索结果"
          closeText="关闭搜索结果"
          clearText="清除搜索"
          inputValue={query}
          onInputChange={(_, value) => setQuery(value)}
          onChange={(_, value) => value && redirect(value.path.replace(/^\/admin(?=\/|$)/, "") || "/")}
          getOptionLabel={(option) => option.label}
          renderOption={(props, option) => (
            <li {...props} key={`${option.resource}-${option.id}`}>
              <Box><Typography variant="body2" fontWeight={600}>{option.title}</Typography><Typography variant="caption" color="text.secondary">{option.subtitle ?? option.resource}</Typography></Box>
            </li>
          )}
          renderInput={(params) => <TextField {...params} placeholder="搜索帖子、用户、名录…" slotProps={{ htmlInput: { ...params.inputProps, maxLength: 100 }, input: { ...params.InputProps, startAdornment: <><Search fontSize="small" />{params.InputProps.startAdornment}</> } }} />}
        />
        <Select
          size="small"
          value={campusID}
          onChange={(event) => {
            const value = String(event.target.value);
            setCampusID(value);
            saveCampusScope(value);
            refresh();
          }}
          sx={{ minWidth: { xs: 112, md: 150 } }}
        >
          <MenuItem value="all">全部学校</MenuItem>
          {campuses.filter((campus) => campus.id !== "general").map((campus) => <MenuItem key={campus.id} value={campus.id}>{campus.display_name}</MenuItem>)}
        </Select>
      </Stack>
    </AppBar>
  );
}

const groups = [
  { label: "概览", items: [["/", "总览", <Dashboard />], ["/manual", "手册", <MenuBook />]] },
  { label: "社区运营", items: [["/campuses", "学校", <Apartment />], ["/posts", "帖子", <Chat />], ["/polls", "投票", <Poll />], ["/comments", "评论", <Comment />], ["/reports", "举报", <Flag />], ["/profiles", "用户", <AccountCircle />], ["/feedback", "反馈", <RateReview />], ["/announcements", "公告", <Campaign />]] },
  { label: "资料名录", items: [["/postgraduate", "考研信息", <School />], ["/suggestions", "名录建议", <FactCheck />], ["/teachers", "教师", <HowToReg />], ["/courses", "课程", <LibraryBooks />], ["/dishes", "菜品", <FoodBank />], ["/ratings", "评分", <Star />]] },
  { label: "运行配置", items: [["/semester-configs", "学期配置", <Settings />], ["/national-calendar", "国家日历", <Event />]] },
  { label: "系统管理", items: [["/admins", "管理员", <ManageAccounts />], ["/sessions", "会话", <Assessment />], ["/audit-logs", "审计日志", <History />]] },
] as const;

function AdminMenu() {
  return (
    <Menu>
      {groups.map((group) => (
        <Box key={group.label} mb={1.5}>
          <Typography variant="overline" color="text.secondary" px={2.5}>{group.label}</Typography>
          {group.items.map(([to, label, icon]) => <PermissionMenuItem key={to} to={to} label={label} icon={icon} />)}
        </Box>
      ))}
    </Menu>
  );
}

function PermissionMenuItem({ to, label, icon }: { to: string; label: string; icon: React.ReactNode }) {
  const resource = to === "/" ? "dashboard" : to.slice(1);
  const { canAccess, isPending } = useCanAccess({ resource, action: "list" });
  if (isPending || !canAccess) return null;
  return <Menu.Item to={to} primaryText={label} leftIcon={icon} />;
}
