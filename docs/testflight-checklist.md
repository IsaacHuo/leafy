# Leafy TestFlight 检查清单

每次上传 TestFlight 前按本清单检查。

## 1. Xcode 和配置

- `IPHONEOS_DEPLOYMENT_TARGET` 是 `17.0`。
- `MARKETING_VERSION` 是本次对外版本。
- `CURRENT_PROJECT_VERSION` 大于上一次上传的 TestFlight build。
- Bundle identifier 与 App Store Connect 记录一致。
- `Config/Leafy.local.xcconfig` 只存在本地或安全 CI 环境。
- `leafy.xcodeproj/project.pbxproj` 中没有真实 Supabase key。
- Release/TestFlight 使用目标 Supabase 项目的 URL 和 publishable key。

## 2. 网络和隐私

- ATS 配置只为学校强智站点保留必要的 HTTP 访问能力。
- Release/TestFlight 不向用户展示原始 Cookie、session 值、HTML 片段或调试文件路径。
- Release/TestFlight 用户错误文案能区分学校网络、登录态、解析和 Supabase 配置问题。
- TestFlight notes 说明学校数据需要能访问教务系统的网络环境。

## 3. Supabase 后端

- Anonymous sign-ins 已启用。
- Email provider 已启用。
- Email password 与 Magic Link / OTP 已启用，Magic Link 邮件模板展示 `{{ .Token }}`。
- 自定义 SMTP 已接入阿里云 DirectMail / 邮件推送，并完成 SPF、DKIM、MX / 回信地址等 DNS 验证。
- `supabase/migrations/` 已按顺序应用到同一个目标 Supabase 项目。
- `community-bootstrap-user` 已部署。
- 后台相关 Edge Functions 已部署。
- `community-images` bucket 存在并保持私有。
- Storage policies 允许认证用户上传自己命名空间内的社区图片。
- `teachers` 表已导入真实教师名录，或确认评教页会显示空教师状态。
- 已创建至少一位后台超级管理员。

## 4. iOS 手动冒烟

- 验证码加载和刷新正常。
- 学校登录在目标网络下成功。
- 自定义学校注册验证码可在 QQ、163、Gmail 至少各收一次；注册完成后可用邮箱密码重新登录。
- 退出登录后能回到登录页。
- 课表刷新正常；会话失效时要求重新登录。
- 成绩、考试安排、教学计划、培养方案、空教室和校历能打开。
- 校历和作息图可全屏预览、缩放、拖拽和切换。
- 今日课程摘要和课程详情可打开。
- 社区身份 bootstrap 成功。
- 社区资料可完善和再次编辑。
- 发帖、图片上传、评论、点赞、删除可用。
- 通知列表、未读提示、站内公告可用。
- 我的发帖、我的点赞、我的评论可用。
- 老师搜索、老师详情、首次评分和评分更新可用。
- 意见反馈可提交。
- 深色模式和主题色切换后主要页面仍可读。

## 5. 后台手动冒烟

- 后台登录成功。
- 手册页能打开，置顶规则和权限边界显示正常。
- 总览能加载社区指标。
- 帖子和评论可检索。
- 帖子可全局置顶、分类置顶、取消置顶，客户端 Feed 预览排序正确。
- 帖子 / 评论下架和恢复可用。
- 用户禁言和解除禁言可用。
- 反馈可标记和关闭。
- 公告可发布、下线或更新。
- 教师和评分管理可用。
- 审计日志记录关键操作。

## 6. 文档检查

- 根目录只保留 `README.md` 作为文档入口。
- 项目自有 Markdown 文档都在 `docs/` 下。
- 新功能或部署变化已同步到对应文档。
