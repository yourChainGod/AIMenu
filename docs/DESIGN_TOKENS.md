# Copool UI 统一设计规范

**设计时间**: 2026-03-21
**目标平台**: macOS 14+ 菜单栏应用 (SwiftUI)
**适用范围**: Accounts / Providers / Proxy / Settings / Tools 全部 5 个页面

---

## 1. 设计 Token 规范

### 1.1 Opacity 色阶系统 (OpacityScale)

当前代码库中散落 43 种 opacity 值，以下将其收敛为 **10 级标准色阶**。每一级对应明确的语义用途。

| Token 名称 | 数值 | 语义用途 | 替换原有值 |
|---|---|---|---|
| `OpacityScale.ghost` | 0.02 | 极浅底色填充、卡片非激活态 | 0.009, 0.018, 0.02, 0.022, 0.024 |
| `OpacityScale.faint` | 0.04 | 列表行 hover 底色、非激活边框 | 0.035, 0.036, 0.04, 0.045 |
| `OpacityScale.subtle` | 0.06 | Badge/Chip 填充、分隔线、默认边框 | 0.05, 0.055, 0.06, 0.065, 0.07 |
| `OpacityScale.muted` | 0.10 | 激活态 Badge 填充、图标底色、选中 segment | 0.08, 0.09, 0.10, 0.11, 0.12 |
| `OpacityScale.medium` | 0.16 | 当前行高亮、激活态边框 | 0.14, 0.16, 0.17 |
| `OpacityScale.accent` | 0.24 | 弹窗遮罩、强调边框 | 0.20, 0.22, 0.24, 0.28 |
| `OpacityScale.overlay` | 0.42 | 选中项强边框 | 0.42 |
| `OpacityScale.solid` | 0.70 | 次要图标前景 | 0.7 |
| `OpacityScale.dense` | 0.92 | 编辑器文字前景 | 0.92 |
| `OpacityScale.opaque` | 0.97 | 弹窗/卡片背景 | 0.93, 0.96, 0.97, 0.985 |

**SwiftUI 实现:**

```swift
enum OpacityScale {
    static let ghost:  Double = 0.02
    static let faint:  Double = 0.04
    static let subtle: Double = 0.06
    static let muted:  Double = 0.10
    static let medium: Double = 0.16
    static let accent: Double = 0.24
    static let overlay: Double = 0.42
    static let solid:  Double = 0.70
    static let dense:  Double = 0.92
    static let opaque: Double = 0.97
}
```

**渐变规则 (Gradient Policy):**

所有 LinearGradient 的 accent tint 只使用以下两种模式:

| 模式 | 起点色 opacity | 终点色 opacity | 用途 |
|---|---|---|---|
| `subtleGradient` | `ghost` (0.02) | `subtle` (0.06) | 卡片内部输入区、段落背景 |
| `emphasisGradient` | `muted` (0.10) | `ghost` (0.02) | 弹窗顶部、选中态卡片 |

消除一切自由组合的 LinearGradient opacity，统一到上述两种模式。

---

### 1.2 动画预设系统 (AnimationPreset)

当前代码中硬编码了 4 种 Spring 参数和若干 easeInOut，收敛为 **4 个标准动画**:

| Token 名称 | 参数 | 用途 | 替换原有 |
|---|---|---|---|
| `AnimationPreset.snappy` | `.easeInOut(duration: 0.12)` | hover 高亮、微小色彩过渡 | `easeInOut(duration: 0.12)` |
| `AnimationPreset.quick` | `.easeInOut(duration: 0.18)` | Tab 切换、segment 选中、折叠切换 | `easeInOut(duration: 0.18)`, `easeInOut(duration: 0.2)` |
| `AnimationPreset.sheet` | `.spring(response: 0.28, dampingFraction: 0.84)` | 弹窗进出、Modal 展开/收起 | `spring(response: 0.28, dampingFraction: 0.84)` |
| `AnimationPreset.expand` | `.spring(response: 0.32, dampingFraction: 0.82)` | SectionCard 折叠/展开、列表插入/删除 | 任何 >0.28 的 spring |

**SwiftUI 实现:**

```swift
enum AnimationPreset {
    static let snappy: Animation = .easeInOut(duration: 0.12)
    static let quick:  Animation = .easeInOut(duration: 0.18)
    static let sheet:  Animation = .spring(response: 0.28, dampingFraction: 0.84)
    static let expand: Animation = .spring(response: 0.32, dampingFraction: 0.82)
}
```

---

### 1.3 间距系统 (LayoutRules 扩展)

现有 LayoutRules 已定义 4 个值，扩展为完整系统:

| Token | 数值 | 用途 |
|---|---|---|
| `LayoutRules.spacing2` | 2 | 列表行紧凑间距 (LazyVStack) |
| `LayoutRules.spacing4` | 4 | 标签与图标的紧凑间距 |
| `LayoutRules.spacing6` | 6 | Badge 内 HStack 间距、表单 label 与 input 间距 |
| `LayoutRules.spacing8` | 8 | 按钮组间距 |
| `LayoutRules.spacing10` | 10 | 列表行内部 HStack 间距 (listRowSpacing) |
| `LayoutRules.spacing12` | 12 | 表单段落内部 VStack 间距 |
| `LayoutRules.spacing16` | 16 | 页面 padding (pagePadding), 段落间距 (sectionSpacing) |
| `LayoutRules.spacing20` | 20 | Modal 内部 padding |

**圆角系统:**

| Token | 数值 | 用途 |
|---|---|---|
| `LayoutRules.radiusTiny` | 7 | 微型按钮 (providerTinyButton) |
| `LayoutRules.radiusSmall` | 8 | 模型选择 chip |
| `LayoutRules.radiusMedium` | 10 | 输入框、图标底色、segment 内项 |
| `LayoutRules.radiusCard` | 14 | 卡片、段落背景 (cardRadius) |
| `LayoutRules.radiusModal` | 22 | Modal Panel |

---

## 2. 统一组件方案

### 2.1 UnifiedBadge -- 统一 Badge/Chip/Tag

**问题诊断:** 当前存在 3 种实现:

| 组件 | 字号 | 横向 padding | 纵向 padding | 填充 opacity | 边框 opacity | 边框 |
|---|---|---|---|---|---|---|
| `ProviderConfigBadge` | 9.5pt semibold | 7 | 3 | 0.05 | 0.065 | 有 (Capsule) |
| `ToolsStatusBadge` | 10pt semibold | 8 | 4 | 0.1 | 无 | 无 |
| `providerFeatureChip` (行内) | 10pt medium | 6 | 3 | 0.06 | 无 | 无 |
| PresetRow category chip | caption2 semibold | 6 | 3 | 0.06/0.12 | 无 | 无 |
| SkillSheets repo badge | caption2 medium | 8 | 4 | 0.05 | 无 | 无 |

**统一方案: `UnifiedBadge`**

定义两种尺寸变体:

| 变体 | 字号 | 字重 | 水平 padding | 垂直 padding | 填充 opacity | 边框 |
|---|---|---|---|---|---|---|
| `.compact` | 10pt (system) | semibold | 6 | 3 | `subtle` (0.06) | 无 |
| `.standard` | 10pt (system) | semibold | 8 | 4 | `subtle` (0.06) | Capsule strokeBorder, `subtle` (0.06) |

**统一规则:**
- 形状统一为 `Capsule`
- 所有变体使用 `OpacityScale.subtle` (0.06) 作为填充 opacity
- `.standard` 变体增加 strokeBorder 边框，同样使用 `subtle` opacity
- `tint == .secondary` 时文字使用 `.secondary` foregroundStyle，填充/边框使用 `Color.primary`
- 非 secondary 时文字和填充/边框均使用 `tint` 色

**SwiftUI 接口:**

```swift
struct UnifiedBadge: View {
    enum Density { case compact, standard }

    let text: String
    let tint: Color
    var density: Density = .standard

    var body: some View {
        let isSecondary = (tint == .secondary)
        let effectiveTint = isSecondary ? Color.primary : tint

        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isSecondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(tint))
            .padding(.horizontal, density == .compact ? 6 : 8)
            .padding(.vertical, density == .compact ? 3 : 4)
            .background {
                Capsule()
                    .fill(effectiveTint.opacity(OpacityScale.subtle))
                    .overlay {
                        if density == .standard {
                            Capsule()
                                .strokeBorder(effectiveTint.opacity(OpacityScale.subtle), lineWidth: 1)
                        }
                    }
            }
    }
}
```

**迁移映射:**

| 原组件 | 替换为 |
|---|---|
| `ProviderConfigBadge(text:tint:)` | `UnifiedBadge(text:tint:density: .standard)` |
| `ToolsStatusBadge(text:tint:)` | `UnifiedBadge(text:tint:density: .standard)` |
| `providerFeatureChip(text:tint:)` | `UnifiedBadge(text:tint:density: .compact)` |
| PresetRow 内嵌 category chip | `UnifiedBadge(text:tint:density: .compact)` |
| SkillSheets repo label badge | `UnifiedBadge(text:tint:density: .standard)` |

---

### 2.2 UnifiedModalPanel -- 统一弹窗面板

**问题诊断:** 当前存在 3 种弹窗面板实现:

| 面板 | 圆角 | 背景 | 顶部光泽 | 边框 | 阴影 | 关闭按钮 |
|---|---|---|---|---|---|---|
| `ProviderModalPanel` | 22 | windowBG 0.97 + gradient(0.14->0.045->0.02) | 有 (white 0.24->0.02, 110pt) | gradient stroke (accent 0.28->white 0.14->black 0.06) | accent 0.12 r16 + black 0.14 r28 | 无 (外部处理) |
| `ToolsModalPanel` | 22 | windowBG 0.985 + accent 0.03 | 无 | separatorColor 0.14 | black 0.14 r18 | 有 (CloseGlassButton) |
| Proxy Settings Panel | (未读取，推测类似) | -- | -- | -- | -- | -- |

**统一方案: `UnifiedModalPanel`**

保留 `ProviderModalPanel` 的视觉表现力（顶部光泽、渐变边框），因为它最精致；同时内置关闭按钮。

```swift
struct UnifiedModalPanel<Content: View>: View {
    let accent: Color
    let onClose: (() -> Void)?
    @ViewBuilder let content: Content

    init(
        accent: Color,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                // 1. 不透明底色
                RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(OpacityScale.opaque))
                // 2. Accent 渐变色调
                RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(OpacityScale.medium),   // 0.16
                                accent.opacity(OpacityScale.faint),    // 0.04
                                Color.white.opacity(OpacityScale.ghost) // 0.02
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                // 3. 顶部光泽层
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(OpacityScale.accent), // 0.24
                                    Color.white.opacity(OpacityScale.ghost),  // 0.02
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(height: 110)
                    Spacer(minLength: 0)
                }
                // 4. 渐变边框
                RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                accent.opacity(OpacityScale.accent),    // 0.24
                                Color.white.opacity(OpacityScale.medium), // 0.16
                                Color.black.opacity(OpacityScale.subtle) // 0.06
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LayoutRules.radiusModal, style: .continuous))
        .shadow(color: accent.opacity(OpacityScale.muted), radius: 16, x: 0, y: 6)
        .shadow(color: .black.opacity(OpacityScale.medium), radius: 28, x: 0, y: 14)
    }
}
```

**统一弹窗容器函数:**

各页面的 `providerModal` 和 `toolsModal` 函数也应统一。抽取为可复用的 ViewModifier 或共享函数:

```swift
struct ModalOverlay<ModalContent: View>: View {
    let accent: Color
    let onDismiss: () -> Void
    @ViewBuilder let modalContent: ModalContent

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(OpacityScale.accent) // 0.24
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}

                UnifiedModalPanel(accent: accent) {
                    modalContent
                }
                .frame(
                    width: min(max(420, geometry.size.width - 28), 540),
                    height: max(460, geometry.size.height - 28)
                )
                .padding(.horizontal, 14)
                .padding(.top, min(28, max(8, geometry.size.height * 0.04)))
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(
                    .move(edge: .top)
                    .combined(with: .scale(scale: 0.97))
                    .combined(with: .opacity)
                )
            }
            .zIndex(20)
        }
    }
}
```

**弹窗尺寸参数统一:**

| 参数 | 统一值 | 说明 |
|---|---|---|
| 最小宽度 | 420pt | 保证表单可用 |
| 最大宽度 | 540pt | 不超出菜单栏窗口 |
| 水平边距 | 14pt | `geometry.size.width - 28` |
| 最小高度 | 460pt | 保证内容不挤压 |
| 垂直边距 | 14pt (底) | 顶部 4% 窗口高度，最小 8pt，最大 28pt |
| 遮罩 opacity | 0.24 (`accent` 级) | 统一所有弹窗 |
| 过渡动画 | `.move(edge: .top) + .scale(0.97) + .opacity` | 统一过渡 |
| 容器动画 | `AnimationPreset.sheet` | `.spring(response: 0.28, dampingFraction: 0.84)` |

---

### 2.3 UnifiedSectionCard -- 统一表单段落卡片

AddProviderSheet 和 EditProviderSheet 各自实现了 `configSectionCard` / `sectionCard`，逻辑几乎相同。应抽取为共享组件:

```swift
struct FormSectionCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    let icon: String?
    let accent: Color
    var emphasis: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutRules.spacing12) {
            if let title {
                HStack(alignment: .top, spacing: LayoutRules.spacing10) {
                    if let icon {
                        RoundedRectangle(cornerRadius: LayoutRules.radiusMedium, style: .continuous)
                            .fill(accent.opacity(OpacityScale.subtle))
                            .overlay {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                            .frame(width: 26, height: 26)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            content()
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: LayoutRules.radiusCard, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(OpacityScale.opaque),
                            accent.opacity(emphasis ? OpacityScale.faint : OpacityScale.ghost)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LayoutRules.radiusCard, style: .continuous)
                        .strokeBorder(
                            accent.opacity(emphasis ? OpacityScale.muted : OpacityScale.subtle),
                            lineWidth: 1
                        )
                )
        )
        .shadow(
            color: accent.opacity(emphasis ? OpacityScale.ghost : 0.01),
            radius: emphasis ? 10 : 4,
            x: 0,
            y: emphasis ? 4 : 2
        )
    }
}
```

---

### 2.4 清理方案

以下代码应在统一后删除:

| 文件 | 需删除的代码 | 理由 |
|---|---|---|
| `ToolsUIComponents.swift` | `ToolsStatusBadge` 结构体 | 被 `UnifiedBadge` 替换 |
| `ProviderUIComponents.swift` | `ProviderConfigBadge` 结构体 | 被 `UnifiedBadge` 替换 |
| `ProviderPageView.swift` | `providerFeatureChip` 函数 | 被 `UnifiedBadge(density: .compact)` 替换 |
| `ProviderPageView.swift` | `ProviderModalPanel` 私有结构体 | 被 `UnifiedModalPanel` 替换 |
| `ToolsUIComponents.swift` | `ToolsModalPanel` 结构体 | 被 `UnifiedModalPanel` 替换 |
| `ProviderPageView.swift` | `providerModal` 函数 | 被 `ModalOverlay` 替换 |
| `ToolsPageView.swift` | `toolsModal` 函数 | 被 `ModalOverlay` 替换 |
| `ToolsPageView.swift` | `modalTopInset` 函数 | 逻辑内置到 `ModalOverlay` |
| `ProviderPageView.swift` | `modalTopInset` 函数 | 同上 |
| `AddProviderSheet.swift` | `configSectionCard` 函数 | 被 `FormSectionCard` 替换 |
| `EditProviderSheet.swift` | `sectionCard` 函数 | 被 `FormSectionCard` 替换 |
| SectionCard.swift | `glassSelectableCard` modifier | 未使用，直接删除 |
| SectionCard.swift | `frostedCapsuleInput` modifier | 未使用，直接删除 |
| SectionCard.swift | `liquidGlassActionButtonStyle` | 仅为 `aimenuActionButtonStyle` 的 wrapper，删除并直接使用后者 |

---

## 3. 页面交互流程优化

### 3.1 智能嵌合点

#### 3.1.1 Providers + Accounts 联动

**现状:** 用户在 Providers 添加供应商时需手动填写 API Key。Accounts 页面管理的恰好是各服务的登录凭证。

**建议:** 在 AddProviderSheet 的 API Key 字段旁增加"从已有账号导入"快捷按钮。当检测到 Accounts 中有对应 appType 的账号时，自动展示一个下拉选项，一键填入 API Key 和 Base URL。

```
[ API Key * ] [  从已有账号导入 v  ]
                 |  Account A (api.anthropic.com)  |
                 |  Account B (my-proxy.com)       |
```

#### 3.1.2 Providers + Proxy 联动

**现状:** Provider 编辑表单中有独立的 Proxy 配置区域 (proxyHost, proxyPort 等)。Proxy 页面也管理全局代理设置。

**建议:** Provider 表单的 Proxy 部分改为两种模式切换:
- "使用全局代理" -- 自动继承 Proxy 页面的设置
- "自定义代理" -- 保持现有独立配置

这避免用户在两个页面重复配置相同代理信息。

#### 3.1.3 Tools MCP + Providers 联动

**现状:** MCP Server 配置中的 env 字段经常需要填写 API Key，这些 Key 已在 Providers 中存储。

**建议:** MCP Server 编辑器增加"引用 Provider 密钥"功能，允许从已配置的 Provider 中选取 API Key 注入到 env 变量。

### 3.2 简化操作路径

#### 3.2.1 Provider 快速切换

**现状:** 切换 Provider 需要: 进入 Providers 页 -> 找到目标行 -> 点击 checkmark 微型按钮。

**建议:** 在 Header/导航区增加当前 Provider 指示器，点击后弹出快速切换下拉菜单。支持键盘快捷键 (Cmd+1/2/3...) 在同一 appType 的不同 Provider 间切换。

#### 3.2.2 一键测速 + 自动切换

**现状:** 用户先测速全部 Provider，然后手动比较结果，再手动切换到最快的。

**建议:** "全部测速" 完成后，在结果区底部增加 "切换到最快的 Provider" 按钮，一键完成。

#### 3.2.3 表单步骤简化

**现状:** AddProviderSheet 有两步: 选择 Preset -> 填写配置。对于只有 1-2 个 Preset 的 appType (如 Gemini)，选择步骤是多余的。

**建议:**
- 当某 appType 的 featured preset 数量 <= 2 时，跳过 selectPreset 步骤，直接进入 configure 步骤，在顶部展示 Preset 切换 segment
- 当 featured preset > 2 时，保持当前两步流程

#### 3.2.4 Sheet Header 统一信息密度

**现状:** AddProviderSheet 和 EditProviderSheet 的 header 区域使用了大量 Badge 展示元信息 (badge.preset_selection, badge.candidates_format, badge.write_target 等)，信息密度过高。

**建议:**
- Header 仅保留: 图标 + 标题 + 一个主 Badge (appType) + 关闭按钮
- 次要信息 (写入路径、候选数量) 移入段落首行或 tooltip

### 3.3 状态流转统一

所有 5 个页面的弹窗应遵循统一的状态模式:

```
页面内容 (Idle)
    |
    v
[触发] --> 背景模糊 + 遮罩淡入 (AnimationPreset.sheet)
    |
    v
Modal Panel 从顶部滑入 + 缩放 0.97->1.0
    |
    +--- [用户操作: 保存/提交]
    |       |
    |       v
    |   Loading 状态 (按钮 spinner + disabled)
    |       |
    |       +--- [成功] --> Modal 滑出 + 背景恢复
    |       +--- [失败] --> 显示行内错误，保持 Modal
    |
    +--- [用户操作: 取消/关闭]
            |
            v
        Modal 滑出 + 背景恢复 (AnimationPreset.sheet)
```

---

## 4. 实施优先级

### Phase 1: Token 基础设施 (影响面最大，风险最低)

1. 创建 `DesignTokens.swift`，定义 `OpacityScale`、`AnimationPreset`
2. 扩展 `LayoutRules`，增加完整间距和圆角常量
3. 全局搜索替换 hardcoded opacity 值为 token 引用
4. 全局搜索替换 hardcoded animation 参数为 preset 引用

### Phase 2: 组件统一 (中等风险)

1. 创建 `UnifiedBadge`，逐一替换 3 种 Badge 实现
2. 创建 `UnifiedModalPanel` + `ModalOverlay`，逐一替换 3 种弹窗
3. 创建 `FormSectionCard`，替换 Add/Edit Sheet 中重复的段落卡片
4. 删除已废弃的组件和 modifier

### Phase 3: 交互优化 (需要后端配合)

1. Provider-Account 联动（需要 AccountsCoordinator 暴露查询接口）
2. Provider 快速切换下拉
3. 测速后自动切换建议
4. 表单步骤智能跳过

---

## 5. 文件组织建议

```
Sources/AIMenu/DesignSystem/
    DesignTokens.swift          -- OpacityScale, AnimationPreset
    LayoutRules+Extended.swift  -- 间距和圆角扩展 (如 LayoutRules 已在别处定义)
    UnifiedBadge.swift          -- 统一 Badge 组件
    UnifiedModalPanel.swift     -- 统一弹窗面板 + ModalOverlay
    FormSectionCard.swift       -- 统一表单段落卡片
```

所有设计 Token 和共享组件集中在 `DesignSystem/` 目录，避免再次散落到各 Feature 文件中。
