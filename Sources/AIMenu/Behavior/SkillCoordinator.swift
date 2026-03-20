import Foundation

actor SkillCoordinator {
    typealias GitHubFileLoader = @Sendable (String, String, String, String) async throws -> String

    private struct GitHubTreeResponse: Decodable {
        struct Entry: Decodable {
            let path: String
            let type: String
        }

        let tree: [Entry]
    }

    private let configService: ProviderConfigService
    private let gitHubFileLoader: GitHubFileLoader?

    init(
        configService: ProviderConfigService,
        gitHubFileLoader: GitHubFileLoader? = nil
    ) {
        self.configService = configService
        self.gitHubFileLoader = gitHubFileLoader
    }

    // MARK: - Skill Store

    func loadSkillStore() async throws -> SkillStore {
        try await configService.loadSkillStore()
    }

    func saveSkillStore(_ store: SkillStore) async throws {
        try await configService.saveSkillStore(store)
    }

    func listInstalledSkills() async throws -> [InstalledSkill] {
        let store = try await configService.loadSkillStore()
        return store.installedSkills.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Skill Repos

    func addSkillRepo(_ repo: SkillRepo) async throws {
        var store = try await configService.loadSkillStore()
        store.repos.removeAll {
            $0.owner.caseInsensitiveCompare(repo.owner) == .orderedSame &&
                $0.name.caseInsensitiveCompare(repo.name) == .orderedSame
        }
        store.repos.append(repo)
        store.repos.sort {
            "\($0.owner)/\($0.name)".localizedCaseInsensitiveCompare("\($1.owner)/\($1.name)") == .orderedAscending
        }
        try await configService.saveSkillStore(store)
    }

    func removeSkillRepo(owner: String, name: String) async throws {
        var store = try await configService.loadSkillStore()
        store.repos.removeAll {
            $0.owner.caseInsensitiveCompare(owner) == .orderedSame &&
                $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        try await configService.saveSkillStore(store)
    }

    func setSkillRepoEnabled(owner: String, name: String, enabled: Bool) async throws {
        var store = try await configService.loadSkillStore()
        guard let index = store.repos.firstIndex(where: {
            $0.owner.caseInsensitiveCompare(owner) == .orderedSame &&
                $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            throw AppError.invalidData(L10n.tr("error.provider.skill_repo_not_found"))
        }

        store.repos[index].isEnabled = enabled
        try await configService.saveSkillStore(store)
    }

    // MARK: - Skill Discovery

    func discoverAvailableSkills() async throws -> [DiscoverableSkill] {
        let store = try await configService.loadSkillStore()
        let installedByKey = Dictionary(uniqueKeysWithValues: store.installedSkills.map { ($0.key, $0) })

        var discovered: [DiscoverableSkill] = []
        var firstError: Error?

        for repo in store.repos where repo.isEnabled {
            do {
                let repoSkills = try await discoverAvailableSkills(in: repo, installedByKey: installedByKey)
                discovered.append(contentsOf: repoSkills)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        let unique = Dictionary(uniqueKeysWithValues: discovered.map { ($0.key, $0) })
        let merged = unique.values.sorted { lhs, rhs in
            if lhs.isInstalled != rhs.isInstalled {
                return !lhs.isInstalled && rhs.isInstalled
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if merged.isEmpty, let firstError {
            throw firstError
        }

        return merged
    }

    // MARK: - Skill Install / Uninstall

    func installSkill(_ skill: DiscoverableSkill) async throws {
        let installDir = await configService.skillsInstallDirectory
        let fm = FileManager.default
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)

        let tempRoot = fm.temporaryDirectory.appendingPathComponent("aimenu-skill-\(UUID().uuidString)")
        let cloneTarget = tempRoot.appendingPathComponent("repo")
        defer { try? fm.removeItem(at: tempRoot) }

        try fm.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        _ = try CommandRunner.runChecked(
            "/usr/bin/env",
            arguments: [
                "git", "clone",
                "--depth=1",
                "--branch", skill.repoBranch,
                "https://github.com/\(skill.repoOwner)/\(skill.repoName).git",
                cloneTarget.path
            ],
            timeout: 45,
            errorPrefix: "克隆技能仓库失败"
        )

        let sourceDirectory = cloneTarget.appendingPathComponent(skill.directory)
        guard fm.fileExists(atPath: sourceDirectory.path) else {
            throw AppError.fileNotFound(L10n.tr("error.provider.skill_directory_not_found_format", skill.directory))
        }

        var store = try await configService.loadSkillStore()
        if let existing = store.installedSkills.first(where: { $0.key == skill.key }),
           existing.directory != skill.directory {
            let legacyDir = skillDirectoryURL(directory: existing.directory, root: installDir)
            if fm.fileExists(atPath: legacyDir.path) {
                try fm.removeItem(at: legacyDir)
            }
            try await configService.removeInstalledSkillFromApps(directory: existing.directory)
        }

        let targetDir = skillDirectoryURL(directory: skill.directory, root: installDir)
        if fm.fileExists(atPath: targetDir.path) {
            try fm.removeItem(at: targetDir)
        }
        try copyDirectoryReplacingExisting(from: sourceDirectory, to: targetDir)

        let installed = InstalledSkill(
            key: skill.key,
            name: skill.name,
            description: skill.description,
            directory: skill.directory,
            repoOwner: skill.repoOwner,
            repoName: skill.repoName,
            installedAt: Int64(Date().timeIntervalSince1970),
            apps: skill.apps
        )
        store.installedSkills.removeAll { $0.key == skill.key || $0.directory == skill.directory }
        store.installedSkills.append(installed)
        try await configService.saveSkillStore(store)
        try await configService.syncInstalledSkill(installed)
    }

    func uninstallSkill(directory: String) async throws {
        let installDir = await configService.skillsInstallDirectory
        let targetDir = skillDirectoryURL(directory: directory, root: installDir)
        let fm = FileManager.default
        if fm.fileExists(atPath: targetDir.path) {
            try fm.removeItem(at: targetDir)
        }

        try await configService.removeInstalledSkillFromApps(directory: directory)
        var store = try await configService.loadSkillStore()
        store.installedSkills.removeAll { $0.directory == directory }
        try await configService.saveSkillStore(store)
    }

    func toggleSkillApp(directory: String, app: ProviderAppType, enabled: Bool) async throws {
        var store = try await configService.loadSkillStore()
        guard let index = store.installedSkills.firstIndex(where: { $0.directory == directory }) else {
            throw AppError.invalidData(L10n.tr("error.provider.skill_not_found"))
        }

        store.installedSkills[index].apps.setEnabled(enabled, for: app)
        try await configService.saveSkillStore(store)
        try await configService.syncInstalledSkill(store.installedSkills[index])
    }

    func syncInstalledSkillsFromDisk() async throws -> [InstalledSkill] {
        let installDir = await configService.skillsInstallDirectory
        let fm = FileManager.default
        try fm.createDirectory(at: installDir, withIntermediateDirectories: true)

        let existingStore = try await configService.loadSkillStore()
        let existingByDirectory = Dictionary(uniqueKeysWithValues: existingStore.installedSkills.map { ($0.directory, $0) })
        let importedApps = try await importMountedSkillsIfNeeded(into: installDir)

        var scanned: [InstalledSkill] = []
        for url in scanSkillMarkdownFiles(in: installDir) {
            guard url.lastPathComponent == "SKILL.md" else { continue }
            let skillDir = url.deletingLastPathComponent()
            let relativePath = relativeSkillPath(skillDir: skillDir, installDir: installDir)
            let metadata = parseSkillMetadata(at: url)
            let importedToggle = importedApps[relativePath] ?? .none

            if let existing = existingByDirectory[relativePath] {
                var skill = existing
                if metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if skill.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        skill.name = metadata.name
                    }
                } else {
                    skill.name = metadata.name
                }
                if let description = metadata.description?.trimmedNonEmpty {
                    skill.description = description
                } else if skill.description?.trimmedNonEmpty == nil {
                    skill.description = metadata.description
                }
                skill.apps = mergeAppToggles(skill.apps, importedToggle)
                scanned.append(skill)
            } else {
                let apps = importedToggle.hasAnyEnabled ? importedToggle : .claudeOnly
                scanned.append(
                    InstalledSkill(
                        key: "local:\(relativePath)",
                        name: metadata.name,
                        description: metadata.description,
                        directory: relativePath,
                        repoOwner: "",
                        repoName: "",
                        installedAt: Int64(Date().timeIntervalSince1970),
                        apps: apps
                    )
                )
            }
        }

        let merged = scanned.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        var updatedStore = existingStore
        updatedStore.installedSkills = merged
        try await configService.saveSkillStore(updatedStore)

        let mergedDirectories = Set(merged.map(\.directory))
        let removedDirectories = Set(existingStore.installedSkills.map(\.directory)).subtracting(mergedDirectories)
        for directory in removedDirectories {
            try await configService.removeInstalledSkillFromApps(directory: directory)
        }

        for skill in merged {
            try await configService.syncInstalledSkill(skill)
        }

        return merged
    }

    // MARK: - Skill Documents

    func readInstalledSkillDocument(directory: String) async throws -> InstalledSkillDocument {
        let installedSkills = try await listInstalledSkills()
        guard let skill = installedSkills.first(where: { $0.directory == directory }) else {
            throw AppError.fileNotFound(L10n.tr("error.provider.installed_skill_not_found_format", directory))
        }

        let content = try await configService.readInstalledSkillContent(directory: directory)
        let path = await configService.installedSkillMarkdownPath(directory: directory)

        return InstalledSkillDocument(
            skill: skill,
            path: path.path,
            content: content
        )
    }

    func updateInstalledSkillContent(directory: String, content: String) async throws -> InstalledSkillDocument {
        try await configService.writeInstalledSkillContent(directory: directory, content: content)

        var store = try await configService.loadSkillStore()
        guard let index = store.installedSkills.firstIndex(where: { $0.directory == directory }) else {
            throw AppError.fileNotFound(L10n.tr("error.provider.installed_skill_not_found_format", directory))
        }

        let fallbackName = directory.components(separatedBy: "/").last ?? directory
        let metadata = parseSkillMetadata(from: content, fallbackName: fallbackName)
        store.installedSkills[index].name = metadata.name
        store.installedSkills[index].description = metadata.description
        try await configService.saveSkillStore(store)
        try await configService.syncInstalledSkill(store.installedSkills[index])

        let path = await configService.installedSkillMarkdownPath(directory: directory)
        return InstalledSkillDocument(
            skill: store.installedSkills[index],
            path: path.path,
            content: content
        )
    }

    func readDiscoverableSkillDocument(_ skill: DiscoverableSkill) async throws -> DiscoverableSkillPreviewDocument {
        let remotePath = "\(skill.directory)/SKILL.md"
        let content = try await fetchGitHubFile(
            owner: skill.repoOwner,
            repo: skill.repoName,
            branch: skill.repoBranch,
            path: remotePath
        )

        return DiscoverableSkillPreviewDocument(
            skill: skill,
            sourcePath: "\(skill.repoOwner)/\(skill.repoName) @ \(skill.repoBranch) / \(remotePath)",
            content: content
        )
    }

    // MARK: - Private Helpers

    private func parseSkillMetadata(at url: URL) -> (name: String, description: String?) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return (url.deletingLastPathComponent().lastPathComponent, nil)
        }

        return parseSkillMetadata(from: content, fallbackName: url.deletingLastPathComponent().lastPathComponent)
    }

    private func relativeSkillPath(skillDir: URL, installDir: URL) -> String {
        let normalizedSkillPath = skillDir.resolvingSymlinksInPath().path
        let normalizedInstallPath = installDir.resolvingSymlinksInPath().path

        if normalizedSkillPath.hasPrefix(normalizedInstallPath + "/") {
            return String(normalizedSkillPath.dropFirst(normalizedInstallPath.count + 1))
        }

        return skillDir.lastPathComponent
    }

    private func discoverAvailableSkills(
        in repo: SkillRepo,
        installedByKey: [String: InstalledSkill]
    ) async throws -> [DiscoverableSkill] {
        let tree = try await fetchGitHubTree(owner: repo.owner, repo: repo.name, branch: repo.branch)
        let skillPaths = tree
            .filter { $0.type == "blob" && $0.path.hasSuffix("SKILL.md") }
            .map(\.path)

        var discovered: [DiscoverableSkill] = []
        for skillPath in skillPaths {
            let directory = String(skillPath.dropLast("/SKILL.md".count))
            let fallbackName = directory.components(separatedBy: "/").last ?? directory
            let content = try? await fetchGitHubFile(
                owner: repo.owner,
                repo: repo.name,
                branch: repo.branch,
                path: skillPath
            )
            let metadata: (name: String, description: String?) = content.map {
                parseSkillMetadata(from: $0, fallbackName: fallbackName)
            } ?? (
                name: prettifiedSkillName(from: fallbackName),
                description: nil
            )

            let key = "\(repo.owner)/\(repo.name):\(directory)"
            let installed = installedByKey[key]
            discovered.append(
                DiscoverableSkill(
                    key: key,
                    name: metadata.name,
                    description: metadata.description,
                    readmeUrl: "https://github.com/\(repo.owner)/\(repo.name)/tree/\(repo.branch)/\(directory)",
                    repoOwner: repo.owner,
                    repoName: repo.name,
                    repoBranch: repo.branch,
                    directory: directory,
                    isInstalled: installed != nil,
                    apps: installed?.apps ?? .claudeOnly
                )
            )
        }

        return discovered
    }

    private func importMountedSkillsIfNeeded(into installDir: URL) async throws -> [String: MCPAppToggles] {
        let fm = FileManager.default
        var importedApps: [String: MCPAppToggles] = [:]

        for app in ProviderAppType.allCases {
            let appDir = await configService.appSkillsDirectory(for: app)
            guard fm.fileExists(atPath: appDir.path) else { continue }

            for file in scanSkillMarkdownFiles(in: appDir) {
                let skillDir = file.deletingLastPathComponent()
                let relativePath = relativeSkillPath(skillDir: skillDir, installDir: appDir)
                var toggles = importedApps[relativePath] ?? .none
                toggles.setEnabled(true, for: app)
                importedApps[relativePath] = toggles

                let centralizedDirectory = skillDirectoryURL(directory: relativePath, root: installDir)
                if !fm.fileExists(atPath: centralizedDirectory.path) {
                    try copyDirectoryReplacingExisting(from: skillDir, to: centralizedDirectory)
                }
            }
        }

        return importedApps
    }

    private func scanSkillMarkdownFiles(in root: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.lastPathComponent == "SKILL.md" {
                files.append(url)
            }
        }
        return files
    }

    private func skillDirectoryURL(directory: String, root: URL) -> URL {
        directory
            .split(separator: "/")
            .reduce(root) { partialResult, component in
                partialResult.appendingPathComponent(String(component), isDirectory: true)
            }
    }

    private func copyDirectoryReplacingExisting(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }

    private func mergeAppToggles(_ lhs: MCPAppToggles, _ rhs: MCPAppToggles) -> MCPAppToggles {
        MCPAppToggles(
            claude: lhs.claude || rhs.claude,
            codex: lhs.codex || rhs.codex,
            gemini: lhs.gemini || rhs.gemini
        )
    }

    private func fetchGitHubTree(owner: String, repo: String, branch: String) async throws -> [GitHubTreeResponse.Entry] {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1") else {
            throw AppError.invalidData(L10n.tr("error.provider.skill_repo_url_invalid"))
        }

        var request = URLRequest(url: url)
        request.setValue("AIMenu/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AppError.io(L10n.tr("error.provider.skill_repo_fetch_failed_format", String(httpResponse.statusCode)))
        }

        let payload = try JSONDecoder().decode(GitHubTreeResponse.self, from: data)
        return payload.tree
    }

    private func fetchGitHubFile(owner: String, repo: String, branch: String, path: String) async throws -> String {
        if let gitHubFileLoader {
            return try await gitHubFileLoader(owner, repo, branch, path)
        }

        guard let url = URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(path)") else {
            throw AppError.invalidData(L10n.tr("error.provider.skill_file_url_invalid"))
        }

        var request = URLRequest(url: url)
        request.setValue("AIMenu/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw AppError.io(L10n.tr("error.provider.skill_document_fetch_failed_format", String(httpResponse.statusCode)))
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw AppError.invalidData(L10n.tr("error.provider.skill_document_not_utf8"))
        }
        return content
    }

    private func parseSkillMetadata(from content: String, fallbackName: String) -> (name: String, description: String?) {
        let lines = content.components(separatedBy: .newlines)
        let title = (
            lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") })
                .map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
        )?.trimmedNonEmpty ?? prettifiedSkillName(from: fallbackName)

        let description = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") })

        return (title, description)
    }

    private func prettifiedSkillName(from value: String) -> String {
        value
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { fragment in
                guard let first = fragment.first else { return "" }
                return String(first).uppercased() + String(fragment.dropFirst())
            }
            .joined(separator: " ")
    }
}
