import SwiftUI

// MARK: - Provider Preview Block Data

struct ProviderPreviewBlockData {
    let title: String
    let subtitle: String
    let content: String
    let onApply: (String) throws -> Void
}

// MARK: - Provider Modal Inset Surface

struct ProviderInsetSurfaceModifier: ViewModifier {
    let accent: Color
    let cornerRadius: CGFloat
    let emphasis: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor).opacity(OpacityScale.opaque),
                                Color.white.opacity(emphasis ? 0.018 : 0.012),
                                accent.opacity(emphasis ? 0.018 : 0.008)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        emphasis
                            ? accent.opacity(0.14)
                            : Color.primary.opacity(OpacityScale.subtle),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(emphasis ? 0.035 : OpacityScale.ghost),
                radius: emphasis ? 6 : 2,
                x: 0,
                y: emphasis ? 3 : 1
            )
    }
}

extension View {
    func providerInsetSurface(
        accent: Color,
        cornerRadius: CGFloat = 12,
        emphasis: Bool = false
    ) -> some View {
        modifier(
            ProviderInsetSurfaceModifier(
                accent: accent,
                cornerRadius: cornerRadius,
                emphasis: emphasis
            )
        )
    }
}

// MARK: - Provider Config Preview Block

struct ProviderConfigPreviewBlock: View {
    let title: String
    let subtitle: String
    let content: String
    let accent: Color
    let onApply: (String) throws -> Void

    @State private var draft: String
    @State private var lastGeneratedContent: String
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var debounceTask: Task<Void, Never>?
    @State private var draftIsInvalidJSON = false

    init(
        title: String,
        subtitle: String,
        content: String,
        accent: Color,
        onApply: @escaping (String) throws -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
        self.accent = accent
        self.onApply = onApply
        _draft = State(initialValue: content)
        _lastGeneratedContent = State(initialValue: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        UnifiedBadge(text: L10n.tr("providers.preview.badge.editable"), tint: .secondary)
                    }
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Button(L10n.tr("common.copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft, forType: .string)
                        statusIsError = false
                        statusMessage = L10n.tr("providers.preview.copied")
                    }
                    .aimenuActionButtonStyle(density: .compact)

                    Button(L10n.tr("common.reset")) {
                        draft = content
                        lastGeneratedContent = content
                        statusMessage = nil
                        statusIsError = false
                    }
                    .aimenuActionButtonStyle(density: .compact)
                    .disabled(draft == content)

                    Button(L10n.tr("common.apply")) {
                        applyDraft()
                    }
                    .aimenuActionButtonStyle(prominent: true, tint: accent, density: .compact)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: statusIsError ? "exclamationmark.circle.fill" : "pencil.tip.crop.circle")
                        .font(.caption2)
                    Text(statusMessage ?? L10n.tr("providers.preview.status_hint"))
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(statusIsError ? .red : .secondary)

                Spacer(minLength: 0)

                UnifiedBadge(text: L10n.tr("providers.preview.badge.live_editable"), tint: .secondary)
            }

            TextEditor(text: $draft)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.primary.opacity(OpacityScale.dense))
                .scrollContentBackground(.hidden)
                .padding(11)
                .frame(minHeight: 360, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(
                                    draftIsInvalidJSON ? Color.red.opacity(0.4) : Color.primary.opacity(OpacityScale.subtle),
                                    lineWidth: draftIsInvalidJSON ? 1.5 : 1
                                )
                        )
                )
        }
        .padding(11)
        .providerInsetSurface(accent: accent, cornerRadius: 13)
        .onChange(of: content) { _, newValue in
            if draft == lastGeneratedContent {
                draft = newValue
            }
            lastGeneratedContent = newValue
        }
        .onChange(of: draft) { _, _ in
            // Debounce auto-apply: cancel previous and wait 500ms
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                autoApplyDraft()
            }
        }
    }

    private func applyDraft() {
        do {
            try onApply(draft)
            lastGeneratedContent = draft
            statusIsError = false
            draftIsInvalidJSON = false
            statusMessage = L10n.tr("providers.preview.applied")
        } catch {
            statusIsError = true
            draftIsInvalidJSON = true
            statusMessage = error.localizedDescription
        }
    }

    /// Silently auto-apply JSON edits — no error popups, just sync valid JSON to form fields
    private func autoApplyDraft() {
        guard draft != lastGeneratedContent else { return }
        do {
            try onApply(draft)
            lastGeneratedContent = draft
            statusIsError = false
            draftIsInvalidJSON = false
            statusMessage = L10n.tr("providers.preview.applied")
        } catch {
            // Show subtle invalid indicator but don't interrupt typing
            draftIsInvalidJSON = true
        }
    }
}

// MARK: - Provider Model Input Row

struct ProviderModelInputRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isFetching: Bool
    let canFetch: Bool
    let accent: Color
    let onFetch: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .frostedRoundedInput(cornerRadius: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onFetch()
            } label: {
                HStack(spacing: 6) {
                    if isFetching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    Text(L10n.tr("providers.action.fetch_models"))
                        .font(.caption.weight(.semibold))
                }
                .lineLimit(1)
            }
            .aimenuActionButtonStyle(prominent: true, tint: accent, density: .compact)
            .disabled(!canFetch || isFetching)
            .frame(minWidth: 132)
        }
        .padding(10)
        .providerInsetSurface(accent: accent)
    }
}

// MARK: - Claude Common Config Controls

struct ClaudeCommonConfigControls: View {
    @Binding var hideAttribution: Bool
    @Binding var alwaysThinking: Bool
    @Binding var enableTeammates: Bool
    @Binding var applyCommonConfig: Bool
    @Binding var showCommonConfigEditor: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("providers.claude_common.title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                claudeQuickToggle(L10n.tr("providers.claude_common.hide_attribution"), isOn: $hideAttribution)
                claudeQuickToggle(L10n.tr("providers.claude_common.enable_thinking"), isOn: $alwaysThinking)
                claudeQuickToggle(L10n.tr("providers.claude_common.enable_teammates"), isOn: $enableTeammates)
            }
            .font(.subheadline)

            HStack(alignment: .center, spacing: 12) {
                Toggle(L10n.tr("providers.claude_common.write_shared_config"), isOn: $applyCommonConfig)
                    .toggleStyle(.checkbox)
                    .font(.subheadline)

                Button(showCommonConfigEditor ? L10n.tr("providers.claude_common.collapse") : L10n.tr("providers.claude_common.edit")) {
                    if !applyCommonConfig {
                        applyCommonConfig = true
                    }
                    withAnimation(AnimationPreset.quick) {
                        showCommonConfigEditor.toggle()
                    }
                }
                .aimenuActionButtonStyle(density: .compact)

                Spacer(minLength: 0)
            }

            Text(L10n.tr("providers.claude_common.hint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .providerInsetSurface(accent: accent)
    }

    private func claudeQuickToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Provider Model Catalog Service

enum ProviderModelCatalogService {
    private enum ResponseStyle {
        case openAI
        case anthropic
        case gemini
    }

    private struct Endpoint {
        let url: URL
        let style: ResponseStyle
    }

    static func fetch(
        appType: ProviderAppType,
        baseUrl: String,
        apiKey: String,
        claudeApiFormat: ClaudeApiFormat?
    ) async throws -> [String] {
        let endpoint = try resolveEndpoint(
            appType: appType,
            baseUrl: baseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            claudeApiFormat: claudeApiFormat
        )
        var request = URLRequest(url: endpoint.url, timeoutInterval: 15)
        request.httpMethod = "GET"

        switch endpoint.style {
        case .openAI:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            break
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderModelFetchServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ProviderModelFetchServiceError.httpStatus(httpResponse.statusCode)
        }

        let models = try parseModels(from: data, style: endpoint.style)
        return Array(Set(models)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func resolveEndpoint(
        appType: ProviderAppType,
        baseUrl: String,
        apiKey: String,
        claudeApiFormat: ClaudeApiFormat?
    ) throws -> Endpoint {
        switch appType {
        case .claude:
            if claudeApiFormat == .anthropic {
                return Endpoint(url: try anthropicModelsURL(from: baseUrl), style: .anthropic)
            }
            return Endpoint(url: try openAIModelsURL(from: baseUrl, officialHostHint: "openai.com"), style: .openAI)
        case .codex:
            return Endpoint(url: try openAIModelsURL(from: baseUrl, officialHostHint: "openai.com"), style: .openAI)
        case .gemini:
            if baseUrl.contains("generativelanguage.googleapis.com") {
                return Endpoint(url: try geminiModelsURL(from: baseUrl, apiKey: apiKey), style: .gemini)
            }
            return Endpoint(url: try openAIModelsURL(from: baseUrl, officialHostHint: "openai.com"), style: .openAI)
        }
    }

    private static func openAIModelsURL(from baseUrl: String, officialHostHint: String) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedPath = trimmedPath.lowercased()
        let host = components.host?.lowercased() ?? ""

        if lowercasedPath.hasSuffix("models") {
            guard let url = components.url else {
                throw ProviderModelFetchServiceError.invalidBaseURL
            }
            return url
        }

        let newPath: String
        if lowercasedPath.isEmpty, host.contains(officialHostHint) {
            newPath = "/v1/models"
        } else if lowercasedPath.hasSuffix("v1") || lowercasedPath.hasSuffix("v1beta") || lowercasedPath.hasSuffix("v1alpha") {
            newPath = "/\(trimmedPath)/models"
        } else if trimmedPath.isEmpty {
            newPath = "/models"
        } else {
            newPath = "/\(trimmedPath)/models"
        }
        components.path = newPath.replacingOccurrences(of: "//", with: "/")
        guard let url = components.url else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        return url
    }

    private static func anthropicModelsURL(from baseUrl: String) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedPath = trimmedPath.lowercased()

        let newPath: String
        if lowercasedPath.hasSuffix("v1/models") {
            newPath = "/\(trimmedPath)"
        } else if lowercasedPath.hasSuffix("v1") {
            newPath = "/\(trimmedPath)/models"
        } else if trimmedPath.isEmpty {
            newPath = "/v1/models"
        } else {
            newPath = "/\(trimmedPath)/v1/models"
        }
        components.path = newPath.replacingOccurrences(of: "//", with: "/")
        guard let url = components.url else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        return url
    }

    private static func geminiModelsURL(from baseUrl: String, apiKey: String) throws -> URL {
        guard var components = URLComponents(string: baseUrl) else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedPath = trimmedPath.lowercased()

        let newPath: String
        if lowercasedPath.hasSuffix("models") {
            newPath = "/\(trimmedPath)"
        } else if lowercasedPath.hasSuffix("v1beta") || lowercasedPath.hasSuffix("v1") || lowercasedPath.hasSuffix("v1alpha") {
            newPath = "/\(trimmedPath)/models"
        } else if trimmedPath.isEmpty {
            newPath = "/v1beta/models"
        } else {
            newPath = "/\(trimmedPath)/models"
        }
        components.path = newPath.replacingOccurrences(of: "//", with: "/")
        var items = components.queryItems ?? []
        if !apiKey.isEmpty {
            items.append(URLQueryItem(name: "key", value: apiKey))
        }
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else {
            throw ProviderModelFetchServiceError.invalidBaseURL
        }
        return url
    }

    private static func parseModels(from data: Data, style: ResponseStyle) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw ProviderModelFetchServiceError.unsupportedResponse
        }

        switch style {
        case .openAI, .anthropic:
            let list = (dictionary["data"] as? [[String: Any]]) ?? (dictionary["models"] as? [[String: Any]]) ?? []
            let ids = list.compactMap { item -> String? in
                (item["id"] as? String)?.trimmedNonEmpty ?? (item["name"] as? String)?.trimmedNonEmpty
            }
            guard !ids.isEmpty else {
                throw ProviderModelFetchServiceError.unsupportedResponse
            }
            return ids
        case .gemini:
            let list = (dictionary["models"] as? [[String: Any]]) ?? []
            let ids = list.compactMap { item -> String? in
                if let name = (item["name"] as? String)?.trimmedNonEmpty {
                    return name.replacingOccurrences(of: "models/", with: "")
                }
                return (item["id"] as? String)?.trimmedNonEmpty
            }
            guard !ids.isEmpty else {
                throw ProviderModelFetchServiceError.unsupportedResponse
            }
            return ids
        }
    }
}

// MARK: - Provider Model Fetch Service Error

enum ProviderModelFetchServiceError: LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case httpStatus(Int)
    case unsupportedResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return L10n.tr("error.provider.models.invalid_base_url")
        case .invalidResponse:
            return L10n.tr("error.provider.models.invalid_response")
        case .httpStatus(let code):
            return L10n.tr("error.provider.models.http_status_format", String(code))
        case .unsupportedResponse:
            return L10n.tr("error.provider.models.unsupported_response")
        }
    }
}

// MARK: - ProviderAppType Extension

extension ProviderAppType {
    var formAccent: Color {
        switch self {
        case .claude:
            return Color(hex: "#B88B68")
        case .codex:
            return Color(hex: "#5F89E2")
        case .gemini:
            return Color(hex: "#4FA58C")
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .claude:
            return "https://api.anthropic.com"
        case .codex:
            return "https://api.openai.com"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var liveConfigPathsText: String {
        switch self {
        case .claude:
            return "~/.claude/settings.json"
        case .codex:
            return "~/.codex/auth.json + ~/.codex/config.toml"
        case .gemini:
            return "~/.gemini/.env"
        }
    }
}

// MARK: - JSON / TOML / DotEnv Helpers

func prettyJSONString(_ object: [String: Any]) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

func parsedJSONObjectString(_ text: String) -> [String: Any]? {
    guard let normalized = text.trimmedNonEmpty,
          let data = normalized.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return object
}

func normalizedJSONObjectString(_ text: String) -> String? {
    guard let object = parsedJSONObjectString(text) else { return nil }
    return prettyJSONString(object)
}

func extractClaudeCommonConfig(from payload: [String: Any]) -> [String: Any] {
    var common = payload
    common.removeValue(forKey: "env")
    common.removeValue(forKey: "attribution")
    common.removeValue(forKey: "alwaysThinkingEnabled")
    return common
}

func tomlQuoted(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
}

func dotenvEscaped(_ value: String) -> String {
    if value.contains(" ") || value.contains("#") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
    return value
}

// MARK: - Preview Parse Error

enum ProviderPreviewParseError: LocalizedError {
    case invalidJSON
    case invalidJSONObject
    case invalidTOML
    case invalidDotEnv

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return L10n.tr("error.provider.preview.invalid_json")
        case .invalidJSONObject:
            return L10n.tr("error.provider.preview.invalid_json_object")
        case .invalidTOML:
            return L10n.tr("error.provider.preview.invalid_toml")
        case .invalidDotEnv:
            return L10n.tr("error.provider.preview.invalid_env")
        }
    }
}

func parsePreviewJSONObject(_ text: String) throws -> [String: Any] {
    guard let data = text.data(using: .utf8) else {
        throw ProviderPreviewParseError.invalidJSON
    }
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw ProviderPreviewParseError.invalidJSON
    }
    guard let dictionary = object as? [String: Any] else {
        throw ProviderPreviewParseError.invalidJSONObject
    }
    return dictionary
}

func previewString(_ value: Any?) -> String? {
    switch value {
    case let string as String:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}

func previewBool(_ value: Any?) -> Bool {
    switch value {
    case let bool as Bool:
        return bool
    case let string as String:
        return ["1", "true", "yes", "on"].contains(string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    case let number as NSNumber:
        return number.boolValue
    default:
        return false
    }
}

func parsePreviewTOML(_ text: String) throws -> [String: String] {
    var result: [String: String] = [:]

    for rawLine in text.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("[") else { continue }
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = previewUnquoted(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { continue }
        result[key] = value
    }

    guard !result.isEmpty else {
        throw ProviderPreviewParseError.invalidTOML
    }
    return result
}

func parsePreviewDotEnv(_ text: String) throws -> [String: String] {
    var result: [String: String] = [:]

    for rawLine in text.components(separatedBy: .newlines) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.hasPrefix("#") else { continue }
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { continue }
        let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = previewUnquoted(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { continue }
        result[key] = value
    }

    guard !result.isEmpty else {
        throw ProviderPreviewParseError.invalidDotEnv
    }
    return result
}

func previewUnquoted(_ value: String) -> String {
    var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
        trimmed.removeFirst()
        trimmed.removeLast()
        trimmed = trimmed.replacingOccurrences(of: "\\\"", with: "\"")
    }
    return trimmed
}

// MARK: - Provider Segmented Control

struct ProviderSegmentedOption<Selection: Hashable>: Identifiable {
    let title: String
    let value: Selection

    var id: String {
        "\(title)-\(String(describing: value))"
    }
}

struct ProviderSegmentedControl<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [ProviderSegmentedOption<Selection>]
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isSelected = selection == option.value

                Button {
                    withAnimation(AnimationPreset.quick) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 34)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(
                                    isSelected
                                        ? Color(nsColor: .windowBackgroundColor).opacity(OpacityScale.opaque)
                                        : Color.clear
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            isSelected ? accent.opacity(0.16) : Color.primary.opacity(OpacityScale.subtle),
                                            lineWidth: 1
                                        )
                                )
                                .shadow(
                                    color: isSelected ? accent.opacity(0.05) : .clear,
                                    radius: 4,
                                    x: 0,
                                    y: 2
                                )
                        )
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .providerInsetSurface(accent: accent, cornerRadius: 13)
    }
}

// MARK: - Preset Row

struct PresetRow: View {
    let preset: ProviderPreset
    let isSelected: Bool
    let accent: Color

    private var rowTint: Color {
        if let hex = preset.iconColor {
            return Color(hex: hex)
        }
        return accent
    }

    private var hostLabel: String? {
        guard let baseURL = preset.baseUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !baseURL.isEmpty else {
            return preset.category == .custom ? L10n.tr("providers.preset.custom_hint") : nil
        }
        return URL(string: baseURL)?.host ?? baseURL
    }

    private var defaultModelLabel: String? {
        preset.defaultModel?.trimmedNonEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: preset.icon ?? "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? rowTint : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                isSelected
                                    ? rowTint.opacity(0.10)
                                    : Color.primary.opacity(OpacityScale.faint)
                            )
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(preset.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(preset.category.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? rowTint : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background((isSelected ? rowTint : Color.primary).opacity(isSelected ? 0.10 : 0.05), in: Capsule())

                        if preset.isPartner {
                            Text(L10n.tr("providers.preset.partner"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(OpacityScale.subtle), in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? rowTint : Color.secondary.opacity(OpacityScale.solid))
            }

            VStack(alignment: .leading, spacing: 6) {
                if let hostLabel {
                    presetInfoRow(icon: "network", text: hostLabel)
                }
                if let defaultModelLabel {
                    presetInfoRow(icon: "sparkles", text: defaultModelLabel)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 108, alignment: .topLeading)
        .padding(13)
        .providerInsetSurface(accent: rowTint, cornerRadius: 14, emphasis: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private func presetInfoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? rowTint : Color.secondary.opacity(OpacityScale.solid))
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Color Hex Init

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
