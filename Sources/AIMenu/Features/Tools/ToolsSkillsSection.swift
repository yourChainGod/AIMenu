import SwiftUI
import AppKit

struct ToolsSkillsSection: View {
    @ObservedObject var model: ToolsPageModel
    let isWorkbenchMode: Bool

    @Binding var skillsExpanded: Bool
    @Binding var showSkillRepoEditor: Bool
    @Binding var hoveredSkill: String?
    @Binding var hoveredDiscoverableSkill: String?
    @Binding var skillsSearchText: String
    @Binding var selectedSkillsFilter: SkillsFilter

    // Cached filtered results – updated only when inputs change
    @State private var cachedFilteredInstalled: [InstalledSkill] = []
    @State private var cachedFilteredDiscoverable: [DiscoverableSkill] = []
    @State private var cachedVisibleInstalled: [InstalledSkill] = []
    @State private var cachedVisibleDiscoverable: [DiscoverableSkill] = []

    var body: some View {
        SectionCard(
            title: "快捷技能",
            icon: "wand.and.stars",
            iconColor: .orange,
            headerTrailing: {
                if isWorkbenchMode {
                    HStack(spacing: 6) {
                        ToolsHelpers.workbenchActionButton(
                            model.skillDiscoveryLoading ? "发现中" : "发现",
                            systemImage: "sparkles",
                            tint: .orange,
                            prominent: true,
                            help: "发现可安装技能"
                        ) {
                            Task { await model.discoverSkills() }
                        }
                        .disabled(model.skillDiscoveryLoading)

                        ToolsHelpers.workbenchActionButton(
                            "扫描",
                            systemImage: "arrow.clockwise",
                            help: "扫描 ~/.claude/skills"
                        ) {
                            Task { await model.refreshSkillsFromDisk() }
                        }

                        ToolsHelpers.workbenchMoreMenu(help: "更多 Skills 操作") {
                            Button("添加技能仓库") {
                                showSkillRepoEditor = true
                            }
                            Button("打开技能目录") {
                                NSWorkspace.shared.selectFile(
                                    NSHomeDirectory() + "/.claude/skills",
                                    inFileViewerRootedAtPath: ""
                                )
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Button {
                            Task { await model.discoverSkills() }
                        } label: {
                            if model.skillDiscoveryLoading {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("发现可安装技能")

                        Button {
                            showSkillRepoEditor = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("添加技能仓库")

                        Button {
                            Task { await model.refreshSkillsFromDisk() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("扫描 ~/.claude/skills")

                        Button {
                            NSWorkspace.shared.selectFile(
                                NSHomeDirectory() + "/.claude/skills",
                                inFileViewerRootedAtPath: ""
                            )
                        } label: {
                            Image(systemName: "folder")
                        }
                        .liquidGlassActionButtonStyle(density: .compact)
                        .help("打开技能目录")

                        CollapseChevronButton(isExpanded: skillsExpanded) {
                            withAnimation(AnimationPreset.quick) { skillsExpanded.toggle() }
                        }
                    }
                }
            }
        ) {
            if isWorkbenchMode || skillsExpanded {
                skillsContent
            }
        }
        .onAppear { recomputeFilteredSkills() }
        .onChange(of: skillsSearchText) { _, _ in recomputeFilteredSkills() }
        .onChange(of: selectedSkillsFilter) { _, _ in recomputeVisibleSkills() }
        .onChange(of: model.skills) { _, _ in recomputeFilteredSkills() }
        .onChange(of: model.discoverableSkills) { _, _ in recomputeFilteredSkills() }
    }

    // MARK: - Filtering

    private var hasSkillsSearchQuery: Bool {
        skillsSearchText.trimmedNonEmpty != nil
    }

    private func recomputeFilteredSkills() {
        let query = skillsSearchText.trimmedNonEmpty

        if let query {
            cachedFilteredInstalled = model.skills.installedSkills.filter { skill in
                matchesSkillsSearch(query: query, fields: [
                    skill.name,
                    skill.description,
                    skill.directory,
                    skill.repoOwner,
                    skill.repoName
                ])
            }
            cachedFilteredDiscoverable = model.discoverableSkills.filter { skill in
                matchesSkillsSearch(query: query, fields: [
                    skill.name,
                    skill.description,
                    skill.directory,
                    skill.repoOwner,
                    skill.repoName,
                    skill.repoBranch
                ])
            }
        } else {
            cachedFilteredInstalled = model.skills.installedSkills
            cachedFilteredDiscoverable = model.discoverableSkills
        }

        recomputeVisibleSkills()
    }

    private func recomputeVisibleSkills() {
        switch selectedSkillsFilter {
        case .all:
            cachedVisibleInstalled = cachedFilteredInstalled
            cachedVisibleDiscoverable = cachedFilteredDiscoverable
        case .installed:
            cachedVisibleInstalled = cachedFilteredInstalled
            cachedVisibleDiscoverable = []
        case .discoverable:
            cachedVisibleInstalled = []
            cachedVisibleDiscoverable = cachedFilteredDiscoverable
        }
    }

    private func matchesSkillsSearch(query: String, fields: [String?]) -> Bool {
        fields.contains { field in
            guard let value = field?.trimmedNonEmpty else { return false }
            return value.localizedCaseInsensitiveContains(query)
        }
    }

    private func count(for filter: SkillsFilter) -> Int {
        switch filter {
        case .all:
            return cachedFilteredInstalled.count + cachedFilteredDiscoverable.count
        case .installed:
            return cachedFilteredInstalled.count
        case .discoverable:
            return cachedFilteredDiscoverable.count
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var skillsContent: some View {
        let installed = cachedVisibleInstalled
        let discoverable = cachedVisibleDiscoverable
        VStack(alignment: .leading, spacing: 10) {
            skillReposRow
            skillsSearchRow

            if selectedSkillsFilter != .installed && (model.skillDiscoveryLoading || !model.discoverableSkills.isEmpty) {
                discoverableSkillsPanel(skills: discoverable)
            }

            if hasSkillsSearchQuery && installed.isEmpty && discoverable.isEmpty && !model.skillDiscoveryLoading {
                ToolsHelpers.compactEmptyState(
                    icon: "magnifyingglass",
                    title: "没有匹配的技能",
                    message: "换个关键词，或者切换到其他筛选试试。",
                    tint: .orange
                )
            } else if selectedSkillsFilter == .installed && model.skills.installedSkills.isEmpty {
                ToolsHelpers.compactEmptyState(
                    icon: "wand.and.stars",
                    title: "暂未安装技能",
                    message: "可以先发现可安装技能，再按应用挂载。",
                    tint: .orange
                )
            } else if !installed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("已安装")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(installed.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(OpacityScale.muted), in: Capsule())
                        Spacer(minLength: 0)
                    }

                    VStack(spacing: 2) {
                        ForEach(installed) { skill in
                            skillRow(skill)
                        }
                    }
                }
            } else if selectedSkillsFilter == .discoverable && discoverable.isEmpty && !model.skillDiscoveryLoading {
                EmptyView()
            }
        }
    }

    // MARK: - Search Row

    private var skillsSearchRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.orange.opacity(OpacityScale.dense))

                    TextField("搜索技能、仓库或目录", text: $skillsSearchText)
                        .textFieldStyle(.plain)
                        .font(.subheadline)

                    if !skillsSearchText.isEmpty {
                        Button {
                            skillsSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(OpacityScale.muted))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.orange.opacity(OpacityScale.medium), lineWidth: 1)
                        )
                )

                if !model.skills.installedSkills.isEmpty {
                    skillCountBadge(title: "已装", count: cachedFilteredInstalled.count, tint: .orange)
                }

                if model.skillDiscoveryLoading || !model.discoverableSkills.isEmpty {
                    skillCountBadge(title: "可装", count: cachedFilteredDiscoverable.count, tint: .blue)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SkillsFilter.allCases) { filter in
                        Button {
                            withAnimation(AnimationPreset.hover) {
                                selectedSkillsFilter = filter
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(filter.title)
                                    .font(.caption.weight(.semibold))
                                Text("\(count(for: filter))")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(selectedSkillsFilter == filter ? Color.white.opacity(OpacityScale.dense) : .secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .background(
                            Capsule()
                                .fill(selectedSkillsFilter == filter ? Color.orange.opacity(OpacityScale.dense) : Color.primary.opacity(OpacityScale.subtle))
                        )
                        .foregroundStyle(selectedSkillsFilter == filter ? Color.white : Color.primary)
                    }
                }
            }
        }
    }

    private func skillCountBadge(title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(OpacityScale.muted), in: Capsule())
    }

    // MARK: - Repos Row

    private var skillReposRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.skills.repos) { repo in
                    HStack(spacing: 6) {
                        Button {
                            Task { await model.setSkillRepoEnabled(repo, enabled: !repo.isEnabled) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: repo.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(repo.isEnabled ? .mint : .secondary)
                                Text("\(repo.owner)/\(repo.name)")
                                    .font(.caption.weight(.medium))
                                Text(repo.branch)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(repo.isEnabled ? Color.mint.opacity(OpacityScale.muted) : Color.primary.opacity(OpacityScale.subtle), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        if !repo.isDefault {
                            Button(role: .destructive) {
                                Task { await model.removeSkillRepo(repo) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.red.opacity(OpacityScale.dense))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .opacity(repo.isEnabled ? 1 : OpacityScale.solid)
                }
            }
        }
    }

    // MARK: - Discoverable Skills

    private func discoverableSkillsPanel(skills: [DiscoverableSkill]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("可安装")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(skills.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(OpacityScale.muted), in: Capsule())
                Spacer(minLength: 0)
            }

            if model.skillDiscoveryLoading {
                ToolsHelpers.workbenchStrip(tint: .blue) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在读取技能仓库…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if skills.isEmpty {
                ToolsHelpers.workbenchStrip {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    Text("当前筛选下没有可安装技能")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(skills) { skill in
                        discoverableSkillRow(skill)
                    }
                }
            }
        }
    }

    private func discoverableSkillRow(_ skill: DiscoverableSkill) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(OpacityScale.muted))
                    .frame(width: 32, height: 32)
                Image(systemName: skill.isInstalled ? "checkmark.seal.fill" : "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(skill.isInstalled ? .mint : .blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.subheadline.weight(.medium))
                if let description = skill.description?.trimmedNonEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(skill.repoOwner)/\(skill.repoName) · \(skill.directory)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if skill.isInstalled {
                    Text(L10n.tr("tools.skill.mount_format", skill.apps.displayText))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        ForEach(ProviderAppType.allCases) { app in
                            ToolsHelpers.appMountChip(
                                app: app,
                                isOn: skill.apps.isEnabled(for: app),
                                onChange: { enabled in
                                    model.toggleDiscoverableSkillApp(skillId: skill.id, app: app, enabled: enabled)
                                }
                            )
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    Task { await model.previewDiscoverableSkill(skill) }
                } label: {
                    if model.previewingDiscoverableSkillKey == skill.key {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .help(L10n.tr("tools.skill.preview_help"))
                .disabled(model.previewingDiscoverableSkillKey == skill.key)

                if let urlString = skill.readmeUrl, let url = URL(string: urlString) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .liquidGlassActionButtonStyle(density: .compact)
                    .help(L10n.tr("tools.skill.open_repository_help"))
                }

                if skill.isInstalled {
                    Text(L10n.tr("tools.skill.installed"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.mint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.mint.opacity(OpacityScale.muted), in: Capsule())
                } else {
                    Button(L10n.tr("common.install")) {
                        Task { await model.installSkill(skill) }
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: .blue, density: .compact)
                }
            }
            .opacity(hoveredDiscoverableSkill == skill.id ? 1 : OpacityScale.dense)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await model.previewDiscoverableSkill(skill) }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredDiscoverableSkill == skill.id ? Color.primary.opacity(OpacityScale.subtle) : Color.clear)
        }
        .onHover { hoveredDiscoverableSkill = $0 ? skill.id : nil }
    }

    // MARK: - Installed Skill Row

    private func skillRow(_ skill: InstalledSkill) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(OpacityScale.muted))
                    .frame(width: 32, height: 32)
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(skill.name)
                    .font(.subheadline.weight(.medium))
                if let desc = skill.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(ToolsHelpers.tildePath(ToolsHelpers.installedSkillPath(for: skill)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    ForEach(ProviderAppType.allCases) { app in
                        ToolsHelpers.appMountChip(
                            app: app,
                            isOn: skill.apps.isEnabled(for: app),
                            onChange: { enabled in
                                Task { await model.toggleInstalledSkillApp(directory: skill.directory, app: app, enabled: enabled) }
                            }
                        )
                    }
                }
            }

            Spacer(minLength: 0)

            if let repoLabel = skillRepoLabel(skill) {
                Text(repoLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 4) {
                Button {
                    Task { await model.openInstalledSkill(directory: skill.directory) }
                } label: {
                    Image(systemName: "pencil")
                }
                .liquidGlassActionButtonStyle(density: .compact)

                Button {
                    let path = ToolsHelpers.installedSkillPath(for: skill)
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Image(systemName: "folder")
                }
                .liquidGlassActionButtonStyle(density: .compact)

                Button(role: .destructive) {
                    Task { await model.uninstallSkill(directory: skill.directory) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(OpacityScale.solid))
                }
                .liquidGlassActionButtonStyle(density: .compact)
                .opacity(hoveredSkill == skill.id ? 1 : OpacityScale.accent)
            }
            .animation(AnimationPreset.hover, value: hoveredSkill)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await model.openInstalledSkill(directory: skill.directory) }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredSkill == skill.id ? Color.primary.opacity(OpacityScale.subtle) : Color.clear)
        }
        .onHover { hoveredSkill = $0 ? skill.id : nil }
    }

    private func skillRepoLabel(_ skill: InstalledSkill) -> String? {
        let owner = skill.repoOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let repo = skill.repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty, !repo.isEmpty {
            return "\(owner)/\(repo)"
        }
        return L10n.tr("tools.skill.local")
    }
}
