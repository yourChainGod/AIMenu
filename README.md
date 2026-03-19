# AIMenu

<img src="./AIMenu.png" alt="AIMenu Icon" width="160" />

AIMenu is a macOS menu bar app for managing AI account pools, provider presets, and local proxy access for Codex, Claude Code, Gemini CLI, and related workflows.

AIMenu 是一个面向 macOS 菜单栏的 AI 工具管理器，用来统一管理账号池、提供商预设、本地代理接入，以及 Codex、Claude Code、Gemini CLI 等相关工作流。

## Preview

<img src="./account.png" alt="Accounts Overview" width="560" />
<img src="./account_2.png" alt="Accounts Detail" width="560" />
<img src="./proxy.png" alt="Proxy" width="560" />
<img src="./setting.png" alt="Settings" width="560" />

## What It Does

- Manage account pools and usage-aware routing for API access.
- 为账号池提供统一导入、管理和按用量智能切换。
- Generate and host a local API proxy for Codex and related tools.
- 为 Codex 等工具生成并托管本地集中代理接入。
- Configure Claude, Codex, and Gemini providers with editable JSON, TOML, and ENV previews.
- 用可编辑的 JSON、TOML、ENV 预览来配置 Claude、Codex、Gemini 提供商。
- Maintain MCP/tool presets and keep configuration files aligned with the desktop app state.
- 统一管理 MCP/工具预设，并让配置文件与桌面端状态保持同步。
- Ship as a native SwiftUI macOS app with menu bar integration.
- 基于 SwiftUI 原生实现，并通过菜单栏常驻提供快速入口。

## Tech Stack

- Swift 6
- SwiftUI
- Xcode 17+
- macOS 14+

## Build

```bash
swift build
swift test
xcodebuild -project AIMenu.xcodeproj -scheme AIMenu -destination 'platform=macOS' build
```

Open `AIMenu.xcodeproj` in Xcode and run the `AIMenu` scheme.

使用 Xcode 打开 `AIMenu.xcodeproj`，运行 `AIMenu` scheme 即可。

## Project Structure

- `Sources/AIMenu/App`: app entry, scene composition, tray bootstrap
- `Sources/AIMenu/Features`: account pool, proxy, providers, tools, settings pages
- `Sources/AIMenu/Behavior`: coordinators and workflow orchestration
- `Sources/AIMenu/Infrastructure`: file system, network, process, auth, update integrations
- `Sources/AIMenu/Domain`: models, protocols, localized state definitions
- `Sources/AIMenu/UI`: reusable controls, cards, banners, and interaction styles
- `Sources/AIMenu/Layout`: centralized layout tokens

## Repository

- GitHub: [yourChainGod/AIMenu](https://github.com/yourChainGod/AIMenu)

## Credits

- Inspired in part by earlier community tooling around Codex account and proxy workflows.
- 感谢所有为界面打磨、提供商接入和交互细节提出建议的贡献者与用户。
