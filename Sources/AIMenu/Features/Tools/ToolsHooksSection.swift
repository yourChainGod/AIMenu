import SwiftUI
import AppKit

private struct HookGroup: Equatable {
    let event: String
    let hooks: [ClaudeHook]
}

struct ToolsHooksSection: View {
    @ObservedObject var model: ToolsPageModel
    let isWorkbenchMode: Bool

    @Binding var hooksExpanded: Bool

    // Cached grouped hooks – updated only when model.claudeHooks changes
    @State private var cachedHookGroups: [HookGroup] = []

    var body: some View {
        SectionCard(
            title: "Hooks",
            icon: "point.3.connected.trianglepath.dotted",
            iconColor: .indigo,
            headerTrailing: {
                if isWorkbenchMode {
                    HStack(spacing: 6) {
                        ToolsHelpers.workbenchActionButton(
                            "刷新",
                            systemImage: "arrow.clockwise",
                            tint: .indigo,
                            prominent: true,
                            help: "刷新 Hooks"
                        ) {
                            Task { await model.refreshClaudeHooks() }
                        }

                        ToolsHelpers.workbenchMoreMenu(help: "更多 Hooks 操作") {
                            Button("打开 Claude settings.json") {
                                NSWorkspace.shared.selectFile(NSHomeDirectory() + "/.claude/settings.json", inFileViewerRootedAtPath: "")
                            }
                            Button("打开 Codex hooks.json") {
                                NSWorkspace.shared.selectFile(NSHomeDirectory() + "/.codex/hooks.json", inFileViewerRootedAtPath: "")
                            }
                            Button("打开 Gemini settings.json") {
                                NSWorkspace.shared.selectFile(NSHomeDirectory() + "/.gemini/settings.json", inFileViewerRootedAtPath: "")
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Button {
                            Task { await model.refreshClaudeHooks() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("刷新 Hooks")

                        Button {
                            NSWorkspace.shared.selectFile(NSHomeDirectory() + "/.claude/settings.json", inFileViewerRootedAtPath: "")
                        } label: {
                            Image(systemName: "doc.text")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("打开 Claude settings.json")

                        CollapseChevronButton(isExpanded: hooksExpanded) {
                            withAnimation(AnimationPreset.quick) { hooksExpanded.toggle() }
                        }
                    }
                }
            }
        ) {
            if isWorkbenchMode || hooksExpanded {
                hooksContent
            }
        }
        .onAppear { recomputeHookGroups() }
        .onChange(of: model.claudeHooks) { _, _ in recomputeHookGroups() }
    }

    private func recomputeHookGroups() {
        cachedHookGroups = Dictionary(grouping: model.claudeHooks, by: \.event)
            .map { event, hooks in
                HookGroup(
                    event: event,
                    hooks: hooks.sorted { lhs, rhs in
                        let lhsMatcher = lhs.matcher ?? ""
                        let rhsMatcher = rhs.matcher ?? ""
                        if lhsMatcher != rhsMatcher {
                            return lhsMatcher.localizedCaseInsensitiveCompare(rhsMatcher) == .orderedAscending
                        }
                        return lhs.command.localizedCaseInsensitiveCompare(rhs.command) == .orderedAscending
                    }
                )
            }
            .sorted { lhs, rhs in
                lhs.event.localizedCaseInsensitiveCompare(rhs.event) == .orderedAscending
            }
    }

    @ViewBuilder
    private var hooksContent: some View {
        let hookGroups = cachedHookGroups

        ToolsHelpers.workbenchStrip(tint: .indigo) {
            Label("已挂载", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.weight(.medium))
            ForEach(ProviderAppType.allCases) { app in
                if model.claudeHooks.contains(where: { $0.apps.isEnabled(for: app) }) {
                    UnifiedBadge(text: ToolsHelpers.compactAppName(for: app), tint: ToolsHelpers.localConfigAccent(for: app))
                }
            }
            Text("\(model.claudeHooks.count) 条")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(OpacityScale.subtle), in: Capsule())
            if !hookGroups.isEmpty {
                Text("\(hookGroups.count) 组")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.indigo.opacity(OpacityScale.muted), in: Capsule())
            }
            Spacer(minLength: 0)
        }

        if model.claudeHooks.isEmpty {
            ToolsHelpers.compactEmptyState(
                icon: "point.3.connected.trianglepath.dotted",
                title: "未扫描到 Hooks",
                message: "刷新后会读取 Claude、Codex 与 Gemini 的本地 Hooks。",
                tint: .indigo
            )
        } else {
            VStack(spacing: 8) {
                ForEach(hookGroups, id: \.event) { group in
                    claudeHookGroup(event: group.event, hooks: group.hooks)
                }
            }
        }
    }

    private func claudeHookGroup(event: String, hooks: [ClaudeHook]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                UnifiedBadge(text: event, tint: Color.indigo)
                Text("\(hooks.count) 条")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if hooks.contains(where: { $0.scope == .project }) {
                    UnifiedBadge(text: "含项目级", tint: Color.orange)
                }
            }

            VStack(spacing: 4) {
                ForEach(hooks, id: \.identityKey) { hook in
                    claudeHookRow(hook)
                }
            }
        }
        .padding(8)
        .background(Color.indigo.opacity(OpacityScale.faint), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func claudeHookRow(_ hook: ClaudeHook) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(hook.enabled ? Color.mint : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let matcher = hook.matcher?.trimmedNonEmpty {
                        UnifiedBadge(text: matcher, tint: Color.secondary)
                    }
                    UnifiedBadge(text: hook.scope.displayName, tint: Color.secondary)
                    if let commandType = hook.commandType?.trimmedNonEmpty {
                        UnifiedBadge(text: commandType, tint: Color.blue)
                    }
                    if let timeout = hook.timeout {
                        UnifiedBadge(text: "\(timeout)s", tint: Color.orange)
                    }
                }

                Text(hook.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    ForEach(ProviderAppType.allCases) { app in
                            ToolsHelpers.appMountChip(
                                app: app,
                                isOn: hook.apps.isEnabled(for: app),
                                disabled: !hook.supports(app: app),
                                onChange: { enabled in
                                Task { await model.toggleHookApp(hookIdentity: hook.identityKey, app: app, enabled: enabled) }
                                }
                            )
                        }
                    Spacer(minLength: 0)
                }

                Text(hook.sourcePath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(OpacityScale.faint), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
