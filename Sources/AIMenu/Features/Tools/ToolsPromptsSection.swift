import SwiftUI
import AppKit

struct ToolsPromptsSection: View {
    @ObservedObject var model: ToolsPageModel
    let isWorkbenchMode: Bool

    @Binding var promptsExpanded: Bool
    @Binding var showPromptEditor: Bool
    @Binding var editingPrompt: Prompt?
    @Binding var hoveredPrompt: String?

    var body: some View {
        SectionCard(
            title: "提示词",
            icon: "text.bubble",
            iconColor: .purple,
            headerTrailing: {
                if isWorkbenchMode {
                    HStack(spacing: 6) {
                        ToolsHelpers.workbenchActionButton(
                            "新建",
                            systemImage: "plus",
                            tint: .purple,
                            prominent: true,
                            help: "新建提示词"
                        ) {
                            editingPrompt = nil
                            showPromptEditor = true
                        }

                        ToolsHelpers.workbenchMoreMenu(help: "更多 Prompt 操作") {
                            Button("从 \(model.selectedPromptApp.fileName) 导入") {
                                Task { await model.importLivePrompt() }
                            }
                            Button("打开 \(model.selectedPromptApp.fileName)") {
                                NSWorkspace.shared.selectFile(model.selectedPromptApp.filePath.path, inFileViewerRootedAtPath: "")
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        if promptsExpanded {
                            promptAppPicker
                                .frame(maxWidth: 160)

                            Button {
                                Task { await model.importLivePrompt() }
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                            }
                            .liquidGlassActionButtonStyle(density: .compact)
                            .help("从 \(model.selectedPromptApp.fileName) 导入")

                            Button {
                                NSWorkspace.shared.selectFile(model.selectedPromptApp.filePath.path, inFileViewerRootedAtPath: "")
                            } label: {
                                Image(systemName: "doc.text")
                            }
                            .liquidGlassActionButtonStyle(density: .compact)
                            .help("打开 \(model.selectedPromptApp.fileName)")

                            Button {
                                editingPrompt = nil
                                showPromptEditor = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .liquidGlassActionButtonStyle(density: .compact)
                        }

                        CollapseChevronButton(isExpanded: promptsExpanded) {
                            withAnimation(AnimationPreset.quick) { promptsExpanded.toggle() }
                        }
                    }
                }
            }
        ) {
            if isWorkbenchMode || promptsExpanded {
                promptsContent
            }
        }
    }

    private var promptAppBinding: Binding<PromptAppType> {
        Binding(
            get: { model.selectedPromptApp },
            set: { app in Task { await model.switchPromptApp(app) } }
        )
    }

    private var promptAppPicker: some View {
        Picker("", selection: promptAppBinding) {
            ForEach(PromptAppType.allCases) { app in
                Text(app.displayName).tag(app)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var promptsContent: some View {
        if isWorkbenchMode {
            ToolsHelpers.workbenchStrip(tint: .purple) {
                promptAppPicker
                UnifiedBadge(text: "\(model.prompts.count) 条", tint: .purple)
            }
        }

        promptLiveFileBar

        if model.prompts.isEmpty {
            ToolsHelpers.compactEmptyState(
                icon: "text.bubble",
                title: "暂无提示词",
                message: "点击新建，或从当前应用的文件直接导入。",
                tint: .purple
            )
        } else {
            VStack(spacing: 2) {
                ForEach(model.prompts) { prompt in
                    promptRow(prompt)
                }
            }
        }
    }

    private var promptLiveFileBar: some View {
        ToolsHelpers.workbenchStrip {
            Label(model.selectedPromptApp.fileName, systemImage: "doc.text")
                .font(.caption.weight(.medium))
            Text(model.selectedPromptApp.filePath.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func promptRow(_ prompt: Prompt) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(prompt.isActive ? Color.purple : Color.clear)
                .frame(width: 3, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(prompt.isActive ? .primary : .secondary)

                if let desc = prompt.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !prompt.content.isEmpty {
                    Text(prompt.content)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if prompt.isActive {
                    Text(L10n.tr("tools.prompt.badge.active"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(OpacityScale.muted), in: Capsule())
                }

                Button {
                    Task { await model.activatePrompt(id: prompt.id) }
                } label: {
                    Image(systemName: prompt.isActive ? "checkmark.circle.fill" : "arrow.up.circle")
                        .foregroundStyle(prompt.isActive ? .purple : .secondary)
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .help(
                    prompt.isActive
                        ? L10n.tr("tools.prompt.badge.active")
                        : L10n.tr("tools.prompt.help.activate_format", model.selectedPromptApp.fileName)
                )

                Button {
                    editingPrompt = prompt
                    showPromptEditor = true
                } label: {
                    Image(systemName: "pencil")
                }
                .liquidGlassActionButtonStyle(density: .compact)

                Button(role: .destructive) {
                    Task { await model.deletePrompt(id: prompt.id) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(OpacityScale.solid))
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .opacity(hoveredPrompt == prompt.id ? 1 : OpacityScale.accent)
                .accessibilityLabel(L10n.tr("tools.prompt.delete_accessibility_format", prompt.name))
            }
            .animation(AnimationPreset.hover, value: hoveredPrompt)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredPrompt == prompt.id
                      ? Color.primary.opacity(OpacityScale.subtle)
                      : Color.clear)
        }
        .animation(AnimationPreset.hover, value: hoveredPrompt)
        .onHover { isHovered in hoveredPrompt = isHovered ? prompt.id : nil }
    }
}
