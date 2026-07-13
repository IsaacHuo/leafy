# Supabase 接入

Supabase 承载 MyLeafy 自有的社区、通知、共享、评价、目录、配置和运营数据，不替代学校教务系统，也不应接收学校密码。

## 客户端配置

复制配置模板：

```bash
cp Config/Leafy.example.xcconfig Config/Leafy.local.xcconfig
```

填写：

```xcconfig
SUPABASE_URL = https:/$()/your-project-ref.supabase.co
SUPABASE_PUBLISHABLE_KEY = sb_publishable_xxx
```

只使用 publishable key。`service_role`、数据库连接串和函数私密 secret 必须保留在服务端或安全的 CI secret store。

## 初始化数据库

新环境应从空项目按 migration 顺序建立 schema：

```bash
supabase link --project-ref <project-ref>
supabase db push
```

随后按需要部署 Edge Functions，例如：

```bash
supabase functions deploy community-bootstrap-user
supabase secrets set CAMPUS_AI_TOOL_SIGNING_SECRET=<strong-random-secret>
supabase functions deploy campus-ai-tools
```

具体函数应根据当前版本和目标能力部署，不要把示例命令视为完整生产清单。

## 身份模型

- 学校教务会话与 Supabase Auth 会话彼此独立。
- App 可使用匿名 Supabase 身份启动业务会话。
- 社区 profile 与校园、用户和必要教务标识建立受控绑定。
- 高价值身份能力不能仅依赖客户端“已经登录”的声明。

## 数据安全

| 层级 | 必须落实的控制 |
|---|---|
| Database | 所有暴露表启用 RLS；校验 owner、profile 与 campus scope |
| Storage | 私有 bucket、受控对象路径、signed URL 与独立 policy |
| Edge Functions | 验证 JWT、角色、校园、参数、速率和外部请求范围 |
| Client | 不保存服务端密钥；日志不输出 token、Cookie 或个人数据 |

更新 policy 时尤其要防止用户修改 owner/profile/campus 字段后逃逸原有授权范围。

## 常见故障

| 现象 | 优先检查 |
|---|---|
| 匿名登录失败 | Auth 是否启用 anonymous sign-in，URL 与 key 是否属于同一项目 |
| profile 无法创建 | Function、JWT、migration 和校园记录是否完整 |
| 返回 401/403 | Auth session、RLS、profile 绑定与 campus scope |
| 图片上传后不可见 | bucket、对象路径、signed URL 和 Storage policy |
| Feed 顺序异常 | 服务端 Feed RPC、置顶记录及客户端是否重复排序 |
| 学期数据错位 | active 配置、学期 ID 与真实首周日期 |

完整 schema、RLS、Storage、Functions 和联调说明见仓库[Supabase 文档](https://github.com/IsaacHuo/leafy/blob/main/docs/supabase.md)。


