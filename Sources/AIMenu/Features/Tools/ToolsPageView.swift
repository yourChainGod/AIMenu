import SwiftUI
import AppKit

struct ToolsPageView: View {
    enum PageMode {
        case tools
        case workbench
    }

    @ObservedObject var model: ToolsPageModel
    let mode: PageMode

    @State private var mcpExpanded = true
    @State private var promptsExpanded = true
    @State private var hooksExpanded = true
    @State private var skillsExpanded = true
    @State private var selectedToolsOverviewSection: ToolsOverviewSection = .services
    @State private var showMCPPresets = false
    @State private var showMCPForm = false
    @State private var editingMCPServer: MCPServer?
    @State private var showPromptEditor = false
    @State private var editingPrompt: Prompt?
    @State private var showSkillRepoEditor = false
    @State private var hoveredMCPServer: String? = nil
    @State private var hoveredPrompt: String? = nil
    @State private var hoveredSkill: String? = nil
    @State private var hoveredDiscoverableSkill: String? = nil
    @State private var skillsSearchText = ""
    @State private var selectedSkillsFilter: SkillsFilter = .all

    var body: some View {
        ZStack {
            pageContent
                .blur(radius: hasActiveModal ? 2 : 0)
                .allowsHitTesting(!hasActiveModal)

            if showMCPForm {
                ModalOverlay(accent: .mint, onDismiss: closeMCPForm) {
                    MCPServerEditorSheet(
                        server: editingMCPServer,
                        onSave: { server in
                            Task { await model.saveMCPServer(server) }
                            closeMCPForm()
                        },
                        onCancel: closeMCPForm
                    )
                }
            } else if showPromptEditor {
                ModalOverlay(accent: .purple, onDismiss: closePromptEditor) {
                    PromptEditorSheet(
                        appType: model.selectedPromptApp,
                        prompt: editingPrompt,
                        onSave: { name, content in
                            Task {
                                if let editingPrompt {
                                    var updated = editingPrompt
                                    updated.name = name
                                    updated.content = content
                                    await model.updatePrompt(updated)
                                } else {
                                    await model.addPrompt(name: name, content: content)
                                }
                            }
                            closePromptEditor()
                        },
                        onCancel: closePromptEditor
                    )
                }
            } else if showSkillRepoEditor {
                ModalOverlay(accent: .orange, onDismiss: closeSkillRepoEditor) {
                    SkillRepoEditorSheet(
                        onSave: { owner, name, branch in
                            Task { await model.addSkillRepo(owner: owner, name: name, branch: branch) }
                            closeSkillRepoEditor()
                        },
                        onCancel: closeSkillRepoEditor
                    )
                }
            } else if let document = model.previewingDiscoverableSkillDocument {
                ModalOverlay(accent: .blue, onDismiss: closeDiscoverableSkillPreview) {
                    DiscoverableSkillPreviewSheet(
                        document: document,
                        previewLoading: model.previewingDiscoverableSkillKey == document.skill.key,
                        onInstall: {
                            Task { await model.installSkill(document.skill) }
                        },
                        onDismiss: closeDiscoverableSkillPreview
                    )
                }
            } else if let document = model.editingInstalledSkillDocument {
                ModalOverlay(accent: .orange, onDismiss: closeInstalledSkillEditor) {
                    InstalledSkillEditorSheet(
                        document: document,
                        onSave: { content in
                            Task { await model.saveInstalledSkill(directory: document.skill.directory, content: content) }
                        },
                        onCancel: closeInstalledSkillEditor
                    )
                }
            }
        }
        .task {
            switch mode {
            case .tools:
                await model.loadOverview()
            case .workbench:
                await model.loadWorkbench()
            }
        }
        .animation(AnimationPreset.sheet, value: hasActiveModal)
    }

    // MARK: - Page Content

    private var pageContent: some View {
        ScrollView {
            VStack(spacing: LayoutRules.sectionSpacing) {
                contentSections
            }
            .padding(LayoutRules.pagePadding)
        }
        .scrollIndicators(.hidden)
    }

    private var hasActiveModal: Bool {
        showMCPForm ||
        showPromptEditor ||
        showSkillRepoEditor ||
        model.previewingDiscoverableSkillDocument != nil ||
        model.editingInstalledSkillDocument != nil
    }

    private func closeMCPForm() {
        showMCPForm = false
        editingMCPServer = nil
    }

    private func closePromptEditor() {
        showPromptEditor = false
        editingPrompt = nil
    }

    private func closeSkillRepoEditor() {
        showSkillRepoEditor = false
    }

    private func closeDiscoverableSkillPreview() {
        model.previewingDiscoverableSkillDocument = nil
    }

    private func closeInstalledSkillEditor() {
        model.editingInstalledSkillDocument = nil
    }

    // MARK: - Content Routing

    @ViewBuilder
    private var contentSections: some View {
        switch mode {
        case .tools:
            toolsOverviewSwitcherRow
            toolsOverviewContent
        case .workbench:
            workbenchSwitcherRow
            workbenchContent
        }
    }

    private var workbenchSections: [ToolsPageModel.ToolsSection] {
        [.mcp, .prompts, .hooks, .skills]
    }

    private var activeWorkbenchSection: ToolsPageModel.ToolsSection {
        workbenchSections.contains(model.activeSection) ? model.activeSection : .mcp
    }

    private var isWorkbenchMode: Bool {
        mode == .workbench
    }

    // MARK: - Overview Switcher

    private var toolsOverviewSwitcherRow: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            ForEach(ToolsOverviewSection.allCases) { section in
                Button {
                    withAnimation(AnimationPreset.quick) {
                        selectedToolsOverviewSection = section
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: section.iconName)
                            .font(.caption.weight(.semibold))

                        Text(section.title)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .aimenuActionButtonStyle(
                    prominent: selectedToolsOverviewSection == section,
                    tint: selectedToolsOverviewSection == section ? section.tint : nil,
                    density: .compact
                )
            }
        }
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var toolsOverviewContent: some View {
        switch selectedToolsOverviewSection {
        case .services:
            ToolsServicesSection(model: model)
        case .configs:
            ToolsConfigsSection(model: model)
        }
    }

    // MARK: - Workbench Switcher

    private var workbenchSwitcherRow: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            ForEach(workbenchSections, id: \.self) { section in
                Button {
                    withAnimation(AnimationPreset.quick) {
                        model.activeSection = section
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: workbenchSectionIcon(for: section))
                            .font(.caption.weight(.semibold))

                        Text(workbenchSectionTitle(for: section))
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .aimenuActionButtonStyle(
                    prominent: activeWorkbenchSection == section,
                    tint: activeWorkbenchSection == section ? workbenchSectionTint(for: section) : nil,
                    density: .compact
                )
            }
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var workbenchContent: some View {
        Group {
            switch activeWorkbenchSection {
            case .mcp:
                ToolsMCPServersSection(
                    model: model,
                    isWorkbenchMode: isWorkbenchMode,
                    mcpExpanded: $mcpExpanded,
                    showMCPPresets: $showMCPPresets,
                    showMCPForm: $showMCPForm,
                    editingMCPServer: $editingMCPServer,
                    hoveredMCPServer: $hoveredMCPServer
                )
            case .prompts:
                ToolsPromptsSection(
                    model: model,
                    isWorkbenchMode: isWorkbenchMode,
                    promptsExpanded: $promptsExpanded,
                    showPromptEditor: $showPromptEditor,
                    editingPrompt: $editingPrompt,
                    hoveredPrompt: $hoveredPrompt
                )
            case .hooks:
                ToolsHooksSection(
                    model: model,
                    isWorkbenchMode: isWorkbenchMode,
                    hooksExpanded: $hooksExpanded
                )
            case .skills:
                ToolsSkillsSection(
                    model: model,
                    isWorkbenchMode: isWorkbenchMode,
                    skillsExpanded: $skillsExpanded,
                    showSkillRepoEditor: $showSkillRepoEditor,
                    hoveredSkill: $hoveredSkill,
                    hoveredDiscoverableSkill: $hoveredDiscoverableSkill,
                    skillsSearchText: $skillsSearchText,
                    selectedSkillsFilter: $selectedSkillsFilter
                )
            }
        }
        .id(activeWorkbenchSection.rawValue)
    }

    // MARK: - Workbench Section Metadata

    private func workbenchSectionTitle(for section: ToolsPageModel.ToolsSection) -> String {
        switch section {
        case .mcp:
            return "MCP"
        case .prompts:
            return "Prompts"
        case .hooks:
            return "Hooks"
        case .skills:
            return "Skills"
        }
    }

    private func workbenchSectionIcon(for section: ToolsPageModel.ToolsSection) -> String {
        switch section {
        case .mcp:
            return "server.rack"
        case .prompts:
            return "text.bubble"
        case .hooks:
            return "point.3.connected.trianglepath.dotted"
        case .skills:
            return "wand.and.stars"
        }
    }

    private func workbenchSectionTint(for section: ToolsPageModel.ToolsSection) -> Color {
        switch section {
        case .mcp:
            return .blue
        case .prompts:
            return .purple
        case .hooks:
            return .indigo
        case .skills:
            return .orange
        }
    }
}
