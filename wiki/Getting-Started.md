# 快速开始

本页用于建立本地开发环境。若只需要了解产品，请先阅读[产品总览](Product-Overview)；若需要完整部署后端，请继续阅读 [Supabase 接入](Supabase)。

## 环境要求

- macOS 与 Xcode 26 或更新版本
- iOS 17.0 或更新版本的模拟器或设备
- Git
- Node.js 20.19+，或 Node.js 22.12+（仅官网与运营后台）
- 可用的目标学校教务账号（验证真实教务链路时需要）
- 自建 Supabase 项目（验证社区、共享与运营能力时需要）

项目引用 iOS 26 SDK API，同时为 iOS 17–25 提供运行时回退，因此开发环境需要较新的 Xcode，但部署基线仍为 iOS 17。

## 运行 iOS App

```bash
git clone https://github.com/IsaacHuo/leafy.git
cd leafy
cp Config/Leafy.example.xcconfig Config/Leafy.local.xcconfig
open leafy.xcodeproj
```

编辑 `Config/Leafy.local.xcconfig`：

```xcconfig
SUPABASE_URL = https:/$()/your-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_xxx
```

随后在 Xcode 中选择 `leafy` scheme 和目标设备运行。

### 配置规则

- 只在客户端使用 Supabase publishable key。
- 不要提交 `Leafy.local.xcconfig`、密码、Cookie、证书、描述文件或生产环境密钥。
- 示例配置可用于浏览部分本地页面；社区、共享课表和其他远程功能会进入不可用状态。
- 若 App 提示缺少配置，确认本地 xcconfig 已被 target 引用，且占位值已经替换。

## 运行官网与运营后台

```bash
cd site
npm ci
npm run dev
```

`npm run dev` 适合开发公开网站，或使用 mock API 调试后台界面。需要包含 Cloudflare Pages Functions 的真实管理代理链路时：

```bash
npm run dev:pages
```

运行完整链路前，需要配置 `site/.dev.vars`，并部署对应的 Supabase migration 与 Edge Functions。详见[运营后台](Admin-Console)。

## 常用验证命令

### Web

```bash
cd site
npm run typecheck
npm test
npm run build
npm run test:e2e
```

### Xcode 项目元数据

```bash
xcodebuild -list -project leafy.xcodeproj
```

iOS 完整模拟器构建暂不属于仓库必跑 CI，应根据改动范围在本地选择目标设备验证。

## 推荐阅读顺序

1. [系统架构](Architecture)：先理解学校系统、本地设备、Supabase 和管理端的边界。
2. [设计系统](Design-System)：修改 SwiftUI 页面前确认主题和组件约束。
3. [Supabase 接入](Supabase)：需要社区、共享或云端功能时再配置后端。
4. [贡献指南](Contributing)：提交 Issue 或 PR 前检查分支、测试与敏感信息要求。


