import Foundation

enum ProviderPresets {

    // MARK: - Claude Presets

    static let claudePresets: [ProviderPreset] = [
        ProviderPreset(
            id: "claude-official", name: "Claude Official",
            appType: .claude, category: .official,
            baseUrl: nil, defaultModel: nil,
            websiteUrl: "https://www.anthropic.com/claude-code",
            apiKeyUrl: nil, icon: "c.circle.fill", iconColor: "#D97757",
            isPartner: false, apiFormat: .anthropic, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-deepseek", name: "DeepSeek",
            appType: .claude, category: .cnOfficial,
            baseUrl: "https://api.deepseek.com", defaultModel: "deepseek-chat",
            websiteUrl: "https://platform.deepseek.com",
            apiKeyUrl: "https://platform.deepseek.com/api_keys",
            icon: "d.circle.fill", iconColor: "#4D6BFE",
            isPartner: false, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-zhipu", name: "Zhipu GLM",
            appType: .claude, category: .cnOfficial,
            baseUrl: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4-plus",
            websiteUrl: "https://open.bigmodel.cn",
            apiKeyUrl: "https://open.bigmodel.cn/usercenter/proj-mgmt/apikeys",
            icon: "z.circle.fill", iconColor: "#3B5998",
            isPartner: false, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-kimi", name: "Kimi",
            appType: .claude, category: .cnOfficial,
            baseUrl: "https://api.moonshot.cn/v1", defaultModel: "moonshot-v1-auto",
            websiteUrl: "https://platform.moonshot.cn",
            apiKeyUrl: "https://platform.moonshot.cn/console/api-keys",
            icon: "k.circle.fill", iconColor: "#000000",
            isPartner: false, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-minimax", name: "MiniMax",
            appType: .claude, category: .cnOfficial,
            baseUrl: "https://api.minimax.chat/v1", defaultModel: "MiniMax-M1",
            websiteUrl: "https://platform.minimaxi.com",
            apiKeyUrl: nil, icon: "m.circle.fill", iconColor: "#4A90D9",
            isPartner: true, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-stepfun", name: "StepFun",
            appType: .claude, category: .cnOfficial,
            baseUrl: "https://api.stepfun.com/v1", defaultModel: "step-2-16k",
            websiteUrl: "https://platform.stepfun.ai",
            apiKeyUrl: nil, icon: "s.circle.fill", iconColor: "#00B4D8",
            isPartner: false, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-bailian", name: "Bailian (Aliyun)",
            appType: .claude, category: .cnOfficial,
            baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus",
            websiteUrl: "https://bailian.console.aliyun.com",
            apiKeyUrl: nil, icon: "a.circle.fill", iconColor: "#FF6A00",
            isPartner: false, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-siliconflow", name: "SiliconFlow",
            appType: .claude, category: .aggregator,
            baseUrl: "https://api.siliconflow.cn/v1", defaultModel: nil,
            websiteUrl: "https://siliconflow.cn",
            apiKeyUrl: nil, icon: "s.circle.fill", iconColor: "#6366F1",
            isPartner: true, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-aihubmix", name: "AiHubMix",
            appType: .claude, category: .aggregator,
            baseUrl: "https://aihubmix.com/v1", defaultModel: nil,
            websiteUrl: "https://aihubmix.com",
            apiKeyUrl: nil, icon: "a.circle.fill", iconColor: "#10B981",
            isPartner: false, apiFormat: nil, apiKeyField: .apiKey
        ),
        ProviderPreset(
            id: "claude-openrouter", name: "OpenRouter",
            appType: .claude, category: .aggregator,
            baseUrl: "https://openrouter.ai/api/v1", defaultModel: "anthropic/claude-sonnet-4",
            websiteUrl: "https://openrouter.ai",
            apiKeyUrl: "https://openrouter.ai/settings/keys",
            icon: "o.circle.fill", iconColor: "#6366F1",
            isPartner: false, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-dmxapi", name: "DMXAPI",
            appType: .claude, category: .aggregator,
            baseUrl: "https://www.dmxapi.cn/v1", defaultModel: nil,
            websiteUrl: "https://www.dmxapi.cn",
            apiKeyUrl: nil, icon: "d.circle.fill", iconColor: "#F59E0B",
            isPartner: true
        ),
        ProviderPreset(
            id: "claude-packycode", name: "PackyCode",
            appType: .claude, category: .thirdParty,
            baseUrl: "https://api.packyapi.com", defaultModel: nil,
            websiteUrl: "https://www.packyapi.com",
            apiKeyUrl: nil, icon: "p.circle.fill", iconColor: "#8B5CF6",
            isPartner: true
        ),
        ProviderPreset(
            id: "claude-cubence", name: "Cubence",
            appType: .claude, category: .thirdParty,
            baseUrl: "https://api.cubence.com", defaultModel: nil,
            websiteUrl: "https://cubence.com",
            apiKeyUrl: nil, icon: "c.circle.fill", iconColor: "#06B6D4",
            isPartner: true
        ),
        ProviderPreset(
            id: "claude-aigocode", name: "AIGoCode",
            appType: .claude, category: .thirdParty,
            baseUrl: "https://api.aigocode.com", defaultModel: nil,
            websiteUrl: "https://aigocode.com",
            apiKeyUrl: nil, icon: "a.circle.fill", iconColor: "#22C55E",
            isPartner: true
        ),
        ProviderPreset(
            id: "claude-rightcode", name: "RightCode",
            appType: .claude, category: .thirdParty,
            baseUrl: "https://api.right.codes", defaultModel: nil,
            websiteUrl: "https://www.right.codes",
            apiKeyUrl: nil, icon: "r.circle.fill", iconColor: "#3B82F6",
            isPartner: true
        ),
        ProviderPreset(
            id: "claude-aicodemirror", name: "AICodeMirror",
            appType: .claude, category: .thirdParty,
            baseUrl: "https://api.aicodemirror.com", defaultModel: nil,
            websiteUrl: "https://www.aicodemirror.com",
            apiKeyUrl: nil, icon: "a.circle.fill", iconColor: "#EC4899",
            isPartner: true
        ),
        ProviderPreset(
            id: "claude-aicoding", name: "AICoding",
            appType: .claude, category: .thirdParty,
            baseUrl: "https://api.aicoding.sh", defaultModel: nil,
            websiteUrl: "https://aicoding.sh",
            apiKeyUrl: nil, icon: "a.circle.fill", iconColor: "#14B8A6",
            isPartner: true
        ),
        ProviderPreset(
            id: "claude-crazyrouter", name: "CrazyRouter",
            appType: .claude, category: .thirdParty,
            baseUrl: "https://api.crazyrouter.com", defaultModel: nil,
            websiteUrl: "https://crazyrouter.com",
            apiKeyUrl: nil, icon: "c.circle.fill", iconColor: "#F97316",
            isPartner: true
        ),
        ProviderPreset(
            id: "claude-nvidia", name: "Nvidia NIM",
            appType: .claude, category: .aggregator,
            baseUrl: "https://integrate.api.nvidia.com/v1", defaultModel: nil,
            websiteUrl: "https://build.nvidia.com",
            apiKeyUrl: nil, icon: "n.circle.fill", iconColor: "#76B900",
            isPartner: false, apiFormat: .openaiChat, apiKeyField: .authToken
        ),
        ProviderPreset(
            id: "claude-custom", name: "Custom",
            appType: .claude, category: .custom,
            baseUrl: nil, defaultModel: nil,
            websiteUrl: nil, apiKeyUrl: nil,
            icon: "gearshape.fill", iconColor: "#6B7280",
            isPartner: false
        ),
    ]

    // MARK: - Codex Presets

    static let codexPresets: [ProviderPreset] = [
        ProviderPreset(
            id: "codex-official", name: "OpenAI Official",
            appType: .codex, category: .official,
            baseUrl: nil, defaultModel: nil,
            websiteUrl: "https://platform.openai.com",
            apiKeyUrl: "https://platform.openai.com/api-keys",
            icon: "o.circle.fill", iconColor: "#10A37F",
            isPartner: false, wireApi: "responses"
        ),
        ProviderPreset(
            id: "codex-azure", name: "Azure OpenAI",
            appType: .codex, category: .official,
            baseUrl: nil, defaultModel: nil,
            websiteUrl: "https://azure.microsoft.com/products/ai-services/openai-service",
            apiKeyUrl: nil, icon: "a.circle.fill", iconColor: "#0078D4",
            isPartner: false, wireApi: "responses"
        ),
        ProviderPreset(
            id: "codex-dmxapi", name: "DMXAPI",
            appType: .codex, category: .aggregator,
            baseUrl: "https://www.dmxapi.cn/v1", defaultModel: nil,
            websiteUrl: "https://www.dmxapi.cn",
            apiKeyUrl: nil, icon: "d.circle.fill", iconColor: "#F59E0B",
            isPartner: true, wireApi: "responses"
        ),
        ProviderPreset(
            id: "codex-packycode", name: "PackyCode",
            appType: .codex, category: .thirdParty,
            baseUrl: "https://api.packyapi.com/v1", defaultModel: nil,
            websiteUrl: "https://www.packyapi.com",
            apiKeyUrl: nil, icon: "p.circle.fill", iconColor: "#8B5CF6",
            isPartner: true, wireApi: "responses"
        ),
        ProviderPreset(
            id: "codex-cubence", name: "Cubence",
            appType: .codex, category: .thirdParty,
            baseUrl: "https://api.cubence.com/v1", defaultModel: nil,
            websiteUrl: "https://cubence.com",
            apiKeyUrl: nil, icon: "c.circle.fill", iconColor: "#06B6D4",
            isPartner: true, wireApi: "responses"
        ),
        ProviderPreset(
            id: "codex-aigocode", name: "AIGoCode",
            appType: .codex, category: .thirdParty,
            baseUrl: "https://api.aigocode.com/v1", defaultModel: nil,
            websiteUrl: "https://aigocode.com",
            apiKeyUrl: nil, icon: "a.circle.fill", iconColor: "#22C55E",
            isPartner: true, wireApi: "responses"
        ),
        ProviderPreset(
            id: "codex-openrouter", name: "OpenRouter",
            appType: .codex, category: .aggregator,
            baseUrl: "https://openrouter.ai/api/v1", defaultModel: nil,
            websiteUrl: "https://openrouter.ai",
            apiKeyUrl: "https://openrouter.ai/settings/keys",
            icon: "o.circle.fill", iconColor: "#6366F1",
            isPartner: false, wireApi: "responses"
        ),
        ProviderPreset(
            id: "codex-custom", name: "Custom",
            appType: .codex, category: .custom,
            baseUrl: nil, defaultModel: nil,
            websiteUrl: nil, apiKeyUrl: nil,
            icon: "gearshape.fill", iconColor: "#6B7280",
            isPartner: false, wireApi: "responses"
        ),
    ]

    // MARK: - Gemini Presets

    static let geminiPresets: [ProviderPreset] = [
        ProviderPreset(
            id: "gemini-official", name: "Google Official (OAuth)",
            appType: .gemini, category: .official,
            baseUrl: nil, defaultModel: "gemini-2.5-pro",
            websiteUrl: "https://ai.google.dev",
            apiKeyUrl: nil, icon: "g.circle.fill", iconColor: "#4285F4",
            isPartner: false
        ),
        ProviderPreset(
            id: "gemini-packycode", name: "PackyCode",
            appType: .gemini, category: .thirdParty,
            baseUrl: "https://api.packyapi.com/gemini/v1beta", defaultModel: "gemini-2.5-pro",
            websiteUrl: "https://www.packyapi.com",
            apiKeyUrl: nil, icon: "p.circle.fill", iconColor: "#8B5CF6",
            isPartner: true
        ),
        ProviderPreset(
            id: "gemini-cubence", name: "Cubence",
            appType: .gemini, category: .thirdParty,
            baseUrl: "https://api.cubence.com/gemini/v1beta", defaultModel: "gemini-2.5-pro",
            websiteUrl: "https://cubence.com",
            apiKeyUrl: nil, icon: "c.circle.fill", iconColor: "#06B6D4",
            isPartner: true
        ),
        ProviderPreset(
            id: "gemini-openrouter", name: "OpenRouter",
            appType: .gemini, category: .aggregator,
            baseUrl: "https://openrouter.ai/api/v1", defaultModel: "gemini-2.5-pro",
            websiteUrl: "https://openrouter.ai",
            apiKeyUrl: "https://openrouter.ai/settings/keys",
            icon: "o.circle.fill", iconColor: "#6366F1",
            isPartner: false
        ),
        ProviderPreset(
            id: "gemini-custom", name: "Custom",
            appType: .gemini, category: .custom,
            baseUrl: nil, defaultModel: nil,
            websiteUrl: nil, apiKeyUrl: nil,
            icon: "gearshape.fill", iconColor: "#6B7280",
            isPartner: false
        ),
    ]

    // MARK: - All Presets

    static func presets(for appType: ProviderAppType) -> [ProviderPreset] {
        switch appType {
        case .claude: return claudePresets
        case .codex: return codexPresets
        case .gemini: return geminiPresets
        }
    }

    static var allPresets: [ProviderPreset] {
        claudePresets + codexPresets + geminiPresets
    }

    // MARK: - MCP Presets

    static let mcpPresets: [MCPPreset] = [
        MCPPreset(
            id: "mcp-fetch", name: "Fetch",
            description: "Fetch web content for analysis",
            server: MCPServerSpec(type: .stdio, command: "uvx", args: ["mcp-server-fetch"]),
            defaultApps: .allEnabled,
            homepage: "https://github.com/modelcontextprotocol/servers/tree/main/src/fetch",
            tags: ["web", "fetch"]
        ),
        MCPPreset(
            id: "mcp-filesystem", name: "Filesystem",
            description: "Read/write access to local files",
            server: MCPServerSpec(type: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-filesystem", "/"]),
            defaultApps: .claudeOnly,
            homepage: "https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem",
            tags: ["filesystem", "files"]
        ),
        MCPPreset(
            id: "mcp-memory", name: "Memory",
            description: "Persistent memory using a knowledge graph",
            server: MCPServerSpec(type: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-memory"]),
            defaultApps: .claudeOnly,
            homepage: "https://github.com/modelcontextprotocol/servers/tree/main/src/memory",
            tags: ["memory", "knowledge"]
        ),
        MCPPreset(
            id: "mcp-github", name: "GitHub",
            description: "GitHub API integration",
            server: MCPServerSpec(type: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-github"], env: ["GITHUB_PERSONAL_ACCESS_TOKEN": ""]),
            defaultApps: .allEnabled,
            homepage: "https://github.com/modelcontextprotocol/servers/tree/main/src/github",
            tags: ["github", "git"]
        ),
        MCPPreset(
            id: "mcp-puppeteer", name: "Puppeteer",
            description: "Browser automation and web scraping",
            server: MCPServerSpec(type: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-puppeteer"]),
            defaultApps: .claudeOnly,
            homepage: "https://github.com/modelcontextprotocol/servers/tree/main/src/puppeteer",
            tags: ["browser", "web"]
        ),
        MCPPreset(
            id: "mcp-sequential-thinking", name: "Sequential Thinking",
            description: "Dynamic problem-solving through thought sequences",
            server: MCPServerSpec(type: .stdio, command: "npx", args: ["-y", "@modelcontextprotocol/server-sequential-thinking"]),
            defaultApps: .claudeOnly,
            homepage: "https://github.com/modelcontextprotocol/servers/tree/main/src/sequentialthinking",
            tags: ["thinking", "reasoning"]
        ),
    ]
}
