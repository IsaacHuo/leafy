import { useEffect, useRef, useState } from "react";
import { useDataProvider, useNotify } from "react-admin";
import { Alert, Box, Button, Card, CardContent, CircularProgress, Grid, MenuItem, Stack, TextField, Typography } from "@mui/material";
import type { AdminDataProvider } from "../providers/dataProvider";

type DailyCount = { bucket_date: string; posts: number; comments: number; profiles: number };
type FeedbackAgingBucket = { key: string; label: string; count: number };
type OverviewSummary = {
  operations: { totalProfiles: number; activeProfiles: number; newProfilesToday: number; mutedProfiles: number; postsToday: number; commentsToday: number; daily: DailyCount[] };
  moderation: { openReports: number; overdueReports: number; hiddenPosts: number; pendingPosts: number; hiddenComments: number; publishedComments: number };
  feedback: { open: number; reviewed: number; pending: number; overdue: number; aging: FeedbackAgingBucket[] };
  teachers: { average: number; totalRatings: number };
};
type Overview = {
  summary?: OverviewSummary;
  cards?: {
    profiles?: { total?: number; complete?: number; today?: number; muted?: number };
    posts?: { today?: number; hidden?: number; pendingReview?: number };
    comments?: { today?: number; hidden?: number; published?: number };
    reports?: { open?: number; overdue?: number };
    feedback?: { open?: number; reviewed?: number };
  };
  analytics?: { daily?: DailyCount[]; feedbackAging?: FeedbackAgingBucket[]; teacherRatings?: { average?: number; totalRatings?: number } };
};

export function AdminDashboard() {
  const dataProvider = useDataProvider<AdminDataProvider>();
  const notify = useNotify();
  const [days, setDays] = useState(30);
  const [data, setData] = useState<Overview | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reloadKey, setReloadKey] = useState(0);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    dataProvider.execute<Overview>("overview", { days, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "Asia/Shanghai" })
      .then((value) => !cancelled && setData(value))
      .catch((loadError) => {
        if (cancelled) return;
        const message = loadError instanceof Error ? loadError.message : "总览加载失败。";
        setError(message);
        notify(message, { type: "error" });
      })
      .finally(() => !cancelled && setLoading(false));
    return () => { cancelled = true; };
  }, [dataProvider, days, notify, reloadKey]);

  if (loading && !data) return <Box display="grid" minHeight={320} sx={{ placeItems: "center" }}><CircularProgress /></Box>;
  if (error && !data) return <Alert severity="error" action={<Button color="inherit" onClick={() => setReloadKey((value) => value + 1)}>重试</Button>}>{error}</Alert>;
  const summary = data?.summary ?? fallbackSummary(data);
  const daily = summary.operations?.daily ?? [];
  const feedbackAging = summary.feedback?.aging ?? [];

  return (
    <Stack spacing={3}>
      <Stack direction="row" alignItems="center" justifyContent="space-between">
        <Box><Typography variant="h4" fontWeight={750}>运营总览</Typography><Typography color="text.secondary">增长、审核、反馈与内容健康</Typography></Box>
        <TextField select size="small" label="时间范围" value={days} onChange={(event) => setDays(Number(event.target.value))} sx={{ width: 140 }}>{[7, 30, 90].map((value) => <MenuItem key={value} value={value}>{value} 天</MenuItem>)}</TextField>
      </Stack>
      <Grid container spacing={2}>
        <Metric title="用户总数" value={summary.operations?.totalProfiles} detail={`今日新增 ${summary.operations?.newProfilesToday ?? 0}`} />
        <Metric title="今日内容" value={(summary.operations?.postsToday ?? 0) + (summary.operations?.commentsToday ?? 0)} detail={`帖子 ${summary.operations?.postsToday ?? 0} · 评论 ${summary.operations?.commentsToday ?? 0}`} />
        <Metric title="待处理举报" value={summary.moderation?.openReports} detail={`逾期 ${summary.moderation?.overdueReports ?? 0}`} tone={(summary.moderation?.overdueReports ?? 0) > 0 ? "error.main" : undefined} />
        <Metric title="待处理反馈" value={summary.feedback?.pending} detail={`未查看 ${summary.feedback?.open ?? 0} · 已查看 ${summary.feedback?.reviewed ?? 0} · 逾期 ${summary.feedback?.overdue ?? 0}`} />
      </Grid>
      <Grid container spacing={2}>
        <Grid size={{ xs: 12, lg: 8 }}><ChartCard title={`${days} 天内容趋势`}><EChart empty={daily.length === 0} accessibleLabel={`内容趋势，日期：${daily.map((row) => formatBucketDate(row.bucket_date)).join("、")}`} option={{ tooltip: { trigger: "axis" }, legend: { data: ["帖子", "评论", "用户"] }, xAxis: { type: "category", data: daily.map((row) => formatBucketDate(row.bucket_date)) }, yAxis: { type: "value" }, series: [{ name: "帖子", type: "line", smooth: true, data: daily.map((row) => row.posts ?? 0) }, { name: "评论", type: "line", smooth: true, data: daily.map((row) => row.comments ?? 0) }, { name: "用户", type: "line", smooth: true, data: daily.map((row) => row.profiles ?? 0) }] }} /></ChartCard></Grid>
        <Grid size={{ xs: 12, lg: 4 }}><ChartCard title="反馈等待时长"><EChart empty={feedbackAging.length === 0} accessibleLabel={`反馈等待时长：${feedbackAging.map((row) => `${row.label} ${row.count}`).join("、")}`} option={{ tooltip: { trigger: "axis" }, xAxis: { type: "category", data: feedbackAging.map((row) => row.label ?? row.key) }, yAxis: { type: "value" }, series: [{ type: "bar", data: feedbackAging.map((row) => row.count ?? 0), itemStyle: { color: "#249361" } }] }} /></ChartCard></Grid>
      </Grid>
      <Grid container spacing={2}>
        <Metric title="隐藏帖子" value={summary.moderation?.hiddenPosts} detail={`待审核 ${summary.moderation?.pendingPosts ?? 0}`} />
        <Metric title="隐藏评论" value={summary.moderation?.hiddenComments} detail={`已发布 ${summary.moderation?.publishedComments ?? 0}`} />
        <Metric title="教师评分" value={summary.teachers?.average ?? 0} detail={`${summary.teachers?.totalRatings ?? 0} 条评分`} />
        <Metric title="活跃用户" value={summary.operations?.activeProfiles} detail={`禁言 ${summary.operations?.mutedProfiles ?? 0}`} />
      </Grid>
    </Stack>
  );
}

function Metric({ title, value, detail, tone }: { title: string; value: unknown; detail: string; tone?: string }) {
  return <Grid size={{ xs: 12, sm: 6, lg: 3 }}><Card sx={{ height: "100%" }}><CardContent><Typography color="text.secondary" variant="body2">{title}</Typography><Typography variant="h3" fontWeight={750} color={tone} my={1}>{Number(value ?? 0).toLocaleString()}</Typography><Typography variant="caption" color="text.secondary">{detail}</Typography></CardContent></Card></Grid>;
}

function ChartCard({ title, children }: { title: string; children: React.ReactNode }) {
  return <Card><CardContent><Typography variant="h6" fontWeight={700} mb={2}>{title}</Typography>{children}</CardContent></Card>;
}

function EChart({ option, empty, accessibleLabel }: { option: Record<string, unknown>; empty: boolean; accessibleLabel: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const [error, setError] = useState(false);
  useEffect(() => {
    if (empty) return;
    let disposed = false;
    let chart: { setOption: (value: unknown) => void; resize: () => void; dispose: () => void } | null = null;
    import("./echarts-runtime").then(({ echarts }) => {
      if (!ref.current || disposed) return;
      chart = echarts.init(ref.current);
      chart.setOption(option);
      setError(false);
    }).catch(() => !disposed && setError(true));
    const resize = () => chart?.resize();
    window.addEventListener("resize", resize);
    return () => { disposed = true; window.removeEventListener("resize", resize); chart?.dispose(); };
  }, [empty, option]);
  if (empty) return <Box height={300} display="grid" sx={{ placeItems: "center" }}><Typography color="text.secondary">当前范围暂无数据</Typography></Box>;
  if (error) return <Box height={300} display="grid" sx={{ placeItems: "center" }}><Typography color="error">图表加载失败，请刷新页面重试。</Typography></Box>;
  return <Box ref={ref} height={300} role="img" aria-label={accessibleLabel} />;
}

function fallbackSummary(data: Overview | null) {
  const cards = data?.cards ?? {};
  const analytics = data?.analytics ?? {};
  return {
    operations: { totalProfiles: cards.profiles?.total ?? 0, activeProfiles: cards.profiles?.complete ?? 0, newProfilesToday: cards.profiles?.today ?? 0, mutedProfiles: cards.profiles?.muted ?? 0, postsToday: cards.posts?.today ?? 0, commentsToday: cards.comments?.today ?? 0, daily: analytics.daily ?? [] },
    moderation: { openReports: cards.reports?.open ?? 0, overdueReports: cards.reports?.overdue ?? 0, hiddenPosts: cards.posts?.hidden ?? 0, pendingPosts: cards.posts?.pendingReview ?? 0, hiddenComments: cards.comments?.hidden ?? 0, publishedComments: cards.comments?.published ?? 0 },
    feedback: { open: cards.feedback?.open ?? 0, reviewed: cards.feedback?.reviewed ?? 0, pending: (cards.feedback?.open ?? 0) + (cards.feedback?.reviewed ?? 0), overdue: 0, aging: analytics.feedbackAging ?? [] },
    teachers: { average: analytics.teacherRatings?.average ?? 0, totalRatings: analytics.teacherRatings?.totalRatings ?? 0 },
  };
}

export function formatBucketDate(value: string) {
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  return match ? `${match[2]}-${match[3]}` : "—";
}
