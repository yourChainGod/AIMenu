import Foundation

// MARK: - Static Model Mapping & Reasoning Normalization

extension SwiftNativeProxyRuntimeService {
    static func shouldRetryWithAutoReasoningSummary(statusCode: Int, bodyText: String) -> Bool {
        guard statusCode == 400 else { return false }
        let normalized = bodyText.lowercased()
        return normalized.contains("unsupported value")
            && normalized.contains("none")
            && (normalized.contains("model")
                || normalized.contains("reasoning.summary")
                || normalized.contains("reasoning.effort"))
    }

    static func payloadWithAutoReasoningSummaryIfNeeded(payload: [String: Any]) -> [String: Any]? {
        guard var reasoning = payload["reasoning"] as? [String: Any] else {
            return nil
        }

        let summaryRaw = (reasoning["summary"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let effortRaw = (reasoning["effort"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let shouldFixSummary = summaryRaw == "none"
        let shouldFixEffort = effortRaw == "none"

        guard shouldFixSummary || shouldFixEffort else {
            return nil
        }

        var updated = payload
        if shouldFixSummary {
            reasoning["summary"] = "auto"
        }
        if shouldFixEffort {
            reasoning["effort"] = "medium"
        }
        updated["reasoning"] = reasoning
        return updated
    }

    static func normalizedReasoningSummaryForUpstream(_ summary: String?) -> String {
        let raw = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowered = raw.lowercased()
        if lowered.isEmpty || lowered == "none" {
            return "auto"
        }
        return raw
    }

    static func normalizedReasoningForUpstream(_ reasoning: [String: Any], upstreamModel: String? = nil) -> [String: Any] {
        var result = reasoning
        let effort = normalizedReasoningEffortForUpstream(result["effort"] as? String, upstreamModel: upstreamModel)
        result["effort"] = effort
        let summary = result["summary"] as? String
        result["summary"] = normalizedReasoningSummaryForUpstream(summary)
        return result
    }

    static func normalizedReasoningEffortForUpstream(_ effort: String?, upstreamModel: String? = nil) -> String {
        let raw = effort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let routeFamily = upstreamModel.map(resolveUpstreamRouteFamily(forUpstreamModel:)) ?? .general
        let defaultEffort = defaultReasoningEffortForUpstream(upstreamModel)

        if raw.isEmpty {
            return defaultEffort
        }

        if routeFamily == .codex {
            switch raw {
            case "low", "medium", "high", "xhigh":
                return raw
            case "none", "minimal":
                return defaultEffort
            default:
                return defaultEffort
            }
        }

        switch raw {
        case "none", "minimal", "low", "medium", "high", "xhigh":
            return raw
        default:
            return defaultEffort
        }
    }

    static func defaultReasoningEffortForUpstream(_ upstreamModel: String?) -> String {
        let routeFamily = upstreamModel.map(resolveUpstreamRouteFamily(forUpstreamModel:)) ?? .general
        return routeFamily == .codex ? "medium" : "none"
    }

    static func normalizedForwardHeader(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func resolveUpstreamRouteFamily(forUpstreamModel model: String) -> UpstreamRouteFamily {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.contains("codex")
            || normalized.hasPrefix("gpt-5")
            || normalized.hasPrefix("gpt-5.4")
            || normalized.hasPrefix("gpt5.4")
            || normalized.hasPrefix("gpt-5-4") {
            return .codex
        }
        return .general
    }

    static func resolveUpstreamBaseURL(configuredBaseURL: String, routeFamily: UpstreamRouteFamily) -> String {
        let normalized = normalizeConfiguredBaseURL(configuredBaseURL)
        let backendSuffix = "/backend-api"
        let codexSuffix = "/backend-api/codex"

        switch routeFamily {
        case .codex:
            if normalized.hasSuffix(codexSuffix) {
                return normalized
            }
            if normalized.hasSuffix(backendSuffix) {
                return "\(normalized)/codex"
            }
            return "\(normalized)\(codexSuffix)"
        case .general:
            if normalized.hasSuffix(codexSuffix) {
                return String(normalized.dropLast("/codex".count))
            }
            if normalized.hasSuffix(backendSuffix) {
                return normalized
            }
            return "\(normalized)\(backendSuffix)"
        }
    }

    static func normalizeConfiguredBaseURL(_ configuredBaseURL: String) -> String {
        var trimmed = configuredBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if trimmed.hasSuffix("/backend-api/codex/responses") {
            trimmed = String(trimmed.dropLast("/responses".count))
        } else if trimmed.hasSuffix("/backend-api/responses") {
            trimmed = String(trimmed.dropLast("/responses".count))
        }

        return trimmed
    }
}

// MARK: - Instance Model Mapping Helpers

extension SwiftNativeProxyRuntimeService {
    func normalizeModelForClient(_ model: String) -> String {
        let normalized = model.lowercased()
        if normalized == "gpt5.4" || normalized == "gpt-5.4" {
            return "gpt-5-4"
        }
        return model
    }

    func mapClientModelToUpstream(_ model: String) throws -> String {
        let normalized = normalizedClientModelToken(model)
        if normalized == "gpt-5-4" || normalized == "gpt-5.4" || normalized == "gpt5.4" {
            return "gpt-5.4"
        }
        return normalizedNumericModelRevisionIfNeeded(normalized)
    }

    func normalizedClientModelToken(_ model: String) -> String {
        model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func normalizedNumericModelRevisionIfNeeded(_ normalizedModel: String) -> String {
        guard normalizedModel.hasPrefix("gpt-5-") else {
            return normalizedModel
        }

        let suffix = String(normalizedModel.dropFirst("gpt-5-".count))
        guard let firstSegment = suffix.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first,
              !firstSegment.isEmpty,
              firstSegment.allSatisfy(\.isNumber) else {
            return normalizedModel
        }

        let afterRevision = String(suffix.dropFirst(firstSegment.count))
        return "gpt-5.\(firstSegment)\(afterRevision)"
    }
}
