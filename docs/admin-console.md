# Leafy 运营后台

Leafy 的社区运营后台挂在官网 `/admin`，代码位于 `site/src/admin/`。后台前端只调用 Supabase Edge Functions，不保存或暴露 `service_role`。

## 1. 技术栈

- React 18
- TypeScript
- Vite
- `lucide-react`

本地调试和生产构建都使用官网项目：

```bash
cd site
npm install
npm run dev
npm run build
npm run preview
```

`npm run build` 会先执行 `tsc --noEmit`，再执行 Vite build。

## 2. 环境配置

复制环境变量模板：

```bash
cd site
cp .env.example .env
```

填写：

```text
VITE_SUPABASE_URL=...
VITE_SUPABASE_PUBLISHABLE_KEY=...
```

后台前端只使用 publishable key。高权限逻辑必须放在 Supabase Edge Functions 内。

## 3. 后端前置条件

至少需要：

- 已执行 `supabase/migrations/20260428000200_admin_console.sql`。
- 已执行 `supabase/migrations/20260428000300_admin_console_pgcrypto_search_path.sql`。
- 已执行 `supabase/migrations/20260508000100_admin_analytics.sql`。
- 已部署后台相关 Edge Functions。
- 已创建第一位超级管理员。

部署函数：

```bash
supabase functions deploy admin-login
supabase functions deploy admin-me
supabase functions deploy admin-logout
supabase functions deploy admin-community
supabase functions deploy admin-list-announcements
supabase functions deploy admin-publish-announcement
supabase functions deploy admin-update-announcement
```

创建第一位超级管理员：

```bash
export SUPABASE_DB_URL='postgresql://...'
export ADMIN_USERNAME='admin'
export ADMIN_PASSWORD='replace-with-a-long-password'
export ADMIN_DISPLAY_NAME='Leafy Admin'
bash supabase/scripts/create-admin-account.sh
```

## 4. 模块

当前后台模块：

- 手册：后台日常处理顺序、置顶操作规则、权限边界和常用动作速查。
- 总览：运营健康、审核压力、反馈 SLA、内容质量和教师评分关注项。
- 帖子 / 评论：检索、日期筛选、分页、查看详情、置顶、分类置顶、取消置顶、客户端 Feed 预览、下架、恢复、批量下架和批量恢复。
- 用户：资料检索、日期筛选、分页、详情抽屉、禁言、解除禁言、近期内容和相关审计。
- 反馈：查看、日期筛选、分页、标记已看、关闭。
- 公告：发布、草稿、下线。
- 教师 / 评分：教师名录管理、隐藏恢复、评分明细日期筛选、分页和删除。
- 管理员 / 日志：超级管理员创建账号、停用账号、查看审计日志，日志支持动作和日期筛选。

总览请求 `admin-community` 的 `overview` action，参数为：

```json
{
  "days": 30,
  "timezone": "Asia/Shanghai"
}
```

`days` 只使用 `7`、`30`、`90` 三档；前端默认使用浏览器时区。趋势数据来自只读 RPC：`admin_daily_counts`、`admin_activity_heatmap`、`admin_category_mix`、`admin_top_content`。新前端优先消费 `overview.summary` 分组字段；当远端函数尚未部署新版本时，会从旧 `cards` 和 `analytics` 字段降级生成同样的总览结构。

批量数据库操作只暴露受控 action：

- `bulkModeratePosts({ ids, status, reason })`
- `bulkModerateComments({ ids, status, reason })`
- `pinPost({ postID, scope, category, priority, startsAt, endsAt, reason })`
- `unpinPost({ id })`
- `listPostPins({ postID, status, scope })`
- `getProfile({ id })`

不提供 raw SQL 或任意表编辑器。

### 帖子置顶工作流

1. 在 `帖子` 页筛选 `已发布` 帖子。
2. 选择 `全局置顶` 或 `分类置顶`。
3. 设置整数优先级；数值越大越靠前，优先级相同时开始时间更新的置顶更靠前。
4. 分类置顶必须填写分类；全局置顶不绑定分类。
5. 开始时间留空时由服务端按当前时间生效；结束时间留空表示长期有效。
6. 提交后用帖子页底部的 `客户端 Feed 预览` 检查实际排序；iOS 社区列表会显示 `置顶` 或 `分类置顶` 标识。

置顶只允许作用于 `published` 帖子。取消置顶会把对应 `community_post_pins` 记录标记为 `inactive`，不会删除历史记录。

### 帖子审核与举报工作流

- 图片帖发布时不再进入人工预审；图片上传成功后会自动发布。
- 用户举报帖子后，帖子会先从普通 Feed 下架为 `hidden`，同时生成 `open` 状态的举报记录进入后台审核队列。
- 管理员在 `举报` 页确认后，可以维持下架、恢复内容或进一步禁言用户。

## 5. 安全边界

- 前端不持有 `service_role`。
- 登录、会话校验和管理操作都通过 Edge Functions。
- 管理员密码不写入仓库。
- 管理员操作需要写入审计日志。
- 普通社区 RLS 不应为后台前端放宽；后台能力由服务端函数承担。

## 6. 和 iOS App 的关系

后台和 iOS App 使用同一个 Supabase 项目：

- iOS App 使用匿名会话和 RLS 操作自己的数据。
- 后台使用管理员会话调用 Edge Functions。
- 后台可处理 App 产生的帖子、评论、用户、反馈、公告、教师和评分数据。

后台不参与强智教务登录、课表抓取、成绩抓取或 HTML 解析。

## 7. 部署入口

生产站点部署在 Cloudflare Pages：

- Root directory: `site`
- Build command: `npm run build`
- Output directory: `dist`
- Admin URL: `https://myleafy.space/admin`

后台能力涉及 Edge Function 或 migration 变化时，至少同步部署：

```bash
supabase functions deploy admin-community
supabase functions deploy community-feed
```
