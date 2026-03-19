# AIMenu

<img src="./AIMenu.png" alt="AIMenu Icon" width="156" />

> 上游参考项目
> - [AlickH/Copool](https://github.com/AlickH/Copool)
> - [kongkongyo/cc-switch](https://github.com/kongkongyo/cc-switch)
> - [Moresl/cchub](https://github.com/Moresl/cchub)
> - [yourChainGod/cursor2api-go](https://github.com/yourChainGod/cursor2api-go)
> - [productdevbook/port-killer](https://github.com/productdevbook/port-killer)

AIMenu 是一个面向 macOS 菜单栏的 AI CLI 控制台，用来统一接管 Claude Code、Codex、Gemini 的账号、提供商、集中代理、MCP、提示词、skills 和本地服务。

项目已经移除 iOS / iCloud 方向的残留，专注桌面端本地配置管理与联动体验。

## 它解决什么问题

- AI CLI 的配置文件格式不统一：Claude 用 `settings.json`，Codex 用 `config.toml`，Gemini 常见是 `.env` / `settings.json`。
- 本地代理、账号池、MCP、skills、提示词通常分散在多个文件夹和多个工具里，切换时容易漏改。
- 需要一个更轻、更直观、更接近日常开发流程的原生入口，而不是额外搭一套重后台。

## 当前重点能力

- 账号池
  - 导入和管理本地认证。
  - 展示账号状态、配额窗口和智能切换结果。
- 提供商中心
  - 按 Claude Code、Codex、Gemini 分开管理提供商。
  - 支持预设接入、自定义编辑、自动获取模型。
  - 真实写入对应应用的本地配置文件。
- 集中代理与公网访问
  - 管理 AIMenu 自带的集中代理。
  - Codex 走集中代理接入，不再走本地直配账号。
  - 支持公网访问链路联动。
- 工具管理
  - MCP 统一面板：预设添加、手动编辑、从本地配置导入。
  - Prompt 管理：针对 `CLAUDE.md`、`AGENTS.md`、`GEMINI.md` 的导入、编辑、写入。
  - Hooks 可视化：扫描 `~/.claude/settings.json`，展示事件、matcher、命令和超时。
  - Skills 管理：扫描已安装 skills、发现 GitHub 仓库中的可安装 skills、快速安装/卸载。
  - 本地配置总览：直接查看 Claude / Codex / Gemini 当前 live 文件是否存在，并可快速打开。
- 本地服务
  - 托管 `cursor2api-go` 的下载、安装、启动、停止、配置文件与日志。
  - 一键把 Claude Code 切换到本地 Cursor2API 桥接。
  - 内置端口占用检查与释放，吸收 `port-killer` 的轻量能力。

## 配置写入位置

- Claude Code：`~/.claude/settings.json`
- Codex：`~/.codex/auth.json`、`~/.codex/config.toml`
- Gemini：`~/.gemini/.env`、`~/.gemini/settings.json`
- Prompt 文件：
  - Claude：`~/.claude/CLAUDE.md`
  - Codex：`~/.codex/AGENTS.md`
  - Gemini：`~/.gemini/GEMINI.md`
- Skills：`~/.claude/skills`

## 本地数据目录

- 当前目录：`~/Library/Application Support/AIMenu`
- 兼容迁移：若历史目录仍为 `CodexToolsSwift`，启动时会自动迁移到 `AIMenu`

## 界面方向

- 原生 macOS 菜单栏入口
- 以轻量卡片和短操作链路为主
- 尽量减少解释性文案，优先把常用动作放到一屏内完成
- 保持提供商、代理、工具页的视觉语言一致

## 集成说明

### Cursor2API

AIMenu 不直接内嵌 `cursor2api-go` 源码，而是以“托管外部服务”的方式接入：

- 从 GitHub Release 下载适配当前 macOS 架构的二进制
- 生成默认 `config.yaml`
- 管理启动、停止、健康检查、日志与端口
- 生成受托管的 Claude 提供商并一键应用

### Port Management

AIMenu 吸收了 `port-killer` 的核心开发者场景：

- 查看常用端口是否被占用
- 查看进程名与 PID
- 一键优雅结束并在必要时强制释放
- 追加临时关注端口

## 开发环境

- macOS 14+
- Xcode 17+
- Swift 6

## 构建与测试

```bash
swift build
swift test
xcodebuild -project AIMenu.xcodeproj -scheme AIMenu -destination 'platform=macOS' build
```

## 仓库结构

- `Sources/AIMenu/App`
  - 应用装配、场景入口、菜单栏状态。
- `Sources/AIMenu/Features`
  - 账号池、提供商、代理、工具、设置页面。
- `Sources/AIMenu/Behavior`
  - 协调器与业务编排。
- `Sources/AIMenu/Infrastructure`
  - 文件、网络、命令执行、本地服务与配置落盘。
- `Sources/AIMenu/Domain`
  - 领域模型、协议、配置结构。
- `Tests/AIMenuTests`
  - 核心逻辑与配置相关测试。

## 截图

<img src="./account.png" alt="Accounts Overview" width="560" />
<img src="./account_2.png" alt="Accounts Detail" width="560" />
<img src="./proxy.png" alt="Proxy" width="560" />
<img src="./setting.png" alt="Settings" width="560" />

## 仓库地址

- GitHub: [yourChainGod/AIMenu](https://github.com/yourChainGod/AIMenu)

## 说明

AIMenu 不是对某个上游项目的直接换皮，而是在吸收 Copool、cc-switch、cchub 等项目思路后，围绕 macOS 菜单栏和本地配置联动重新整理的一套实现。欢迎继续提出关于 UI 一致性、配置兼容性和工具编排的改进建议。
