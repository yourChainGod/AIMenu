# AIMenu

<img src="./AIMenu.png" alt="AIMenu Icon" width="156" />

> 上游参考项目
> - [AlickH/Copool](https://github.com/AlickH/Copool)
> - [kongkongyo/cc-switch](https://github.com/kongkongyo/cc-switch)

AIMenu 是一个面向 macOS 菜单栏的 AI 工具控制台，专注把账号池、提供商、集中代理、MCP 工具和本地配置文件管理收拢到一个原生桌面应用里。

项目当前聚焦 macOS 场景，不再保留 iOS / iCloud 相关分支逻辑，强调轻量、直观、可落盘、可联动。

## 项目定位

- 统一管理 Claude Code、Codex、Gemini 的提供商接入与本地配置写入。
- 管理账号池与认证导入，支持按状态和配额进行切换。
- 提供集中代理与公网访问能力，让本地工具接入路径更清晰。
- 在桌面端直接预览和编辑 JSON、TOML、ENV 配置，减少手动改文件的心智负担。
- 用菜单栏常驻入口承载日常运维，而不是做一套厚重的后台系统。

## 核心能力

- 账号池
  - 导入本地认证。
  - 展示账号状态、用量窗口与智能切换结果。
  - 保持界面操作与本地存储同步。
- 提供商中心
  - 为 Claude Code、Codex、Gemini 维护独立提供商列表。
  - 预设快速接入官方、国内官方、聚合与自定义供应商。
  - 自动拉取模型列表，并同步写入对应配置文件。
- 代理与接入
  - 管理本地集中代理。
  - 为 Codex 生成代理型提供商接入。
  - 提供公网访问相关配置与联动状态。
- 工具与 MCP
  - 管理工具预设、提示词和 MCP 服务项。
  - 尽量保证桌面 UI 状态与磁盘配置一致。

## 配置写入

- Claude Code：`~/.claude/settings.json`
- Codex：`~/.codex/auth.json` 和 `~/.codex/config.toml`
- Gemini：`~/.gemini/.env`

其中 Codex 与 Claude Code 的配置策略并不相同。AIMenu 会按应用差异分别生成和更新内容，而不是强行套同一套字段结构。

## 界面预览

<img src="./account.png" alt="Accounts Overview" width="560" />
<img src="./account_2.png" alt="Accounts Detail" width="560" />
<img src="./proxy.png" alt="Proxy" width="560" />
<img src="./setting.png" alt="Settings" width="560" />

## 开发环境

- macOS 14+
- Xcode 17+
- Swift 6

## 构建与测试

```bash
swift build
swift test
xcodebuild -project AIMenu.xcodeproj -scheme AIMenu -destination 'platform=macOS' build
xcodebuild -project AIMenu.xcodeproj -scheme AIMenu -destination 'platform=macOS' test
```

也可以直接使用 Xcode 打开 `AIMenu.xcodeproj`，运行 `AIMenu` scheme。

## 目录结构

- `Sources/AIMenu/App`
  - 应用入口、场景拼装、菜单栏模型。
- `Sources/AIMenu/Features`
  - 账号池、提供商、代理、工具、设置等页面。
- `Sources/AIMenu/Behavior`
  - 协调器与业务编排逻辑。
- `Sources/AIMenu/Infrastructure`
  - 文件、网络、认证、进程、更新检查等底层服务。
- `Sources/AIMenu/Domain`
  - 数据模型、协议、配置结构与领域定义。
- `Sources/AIMenu/UI`
  - 共享组件、按钮样式、卡片与视觉封装。
- `Sources/AIMenu/Layout`
  - 统一布局参数与界面节奏控制。

## 仓库

- GitHub: [yourChainGod/AIMenu](https://github.com/yourChainGod/AIMenu)

## 致谢

本项目吸收了 Copool 与 cc-switch 在账号管理、提供商接入和代理联动方面的思路，并基于 macOS 原生桌面体验继续重构与整合。感谢所有提出交互、配置与兼容性建议的贡献者和用户。
