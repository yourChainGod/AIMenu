import Foundation

// MARK: - Chat ↔ Responses Format Conversion

extension SwiftNativeProxyRuntimeService {
    func normalizeResponsesRequest(_ request: [String: Any]) throws -> (payload: [String: Any], downstreamStream: Bool) {
        guard let rawModel = request["model"] as? String, !rawModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidData(L10n.tr("error.proxy_runtime.missing_model"))
        }
        let model = try mapClientModelToUpstream(rawModel)

        var payload = request
        let downstreamStream = (request["stream"] as? Bool) ?? false

        payload["model"] = model
        payload["stream"] = true
        payload["store"] = false
        if payload["instructions"] == nil {
            payload["instructions"] = ""
        }
        if payload["parallel_tool_calls"] == nil {
            payload["parallel_tool_calls"] = true
        }

        let currentReasoning = payload["reasoning"] as? [String: Any] ?? [:]
        payload["reasoning"] = Self.normalizedReasoningForUpstream(currentReasoning, upstreamModel: model)

        var include = payload["include"] as? [Any] ?? []
        if !include.contains(where: { ($0 as? String) == "reasoning.encrypted_content" }) {
            include.append("reasoning.encrypted_content")
        }
        payload["include"] = include

        return (payload, downstreamStream)
    }

    func convertChatRequestToResponses(_ request: [String: Any]) throws -> (payload: [String: Any], downstreamStream: Bool) {
        if request["messages"] == nil, request["input"] != nil {
            return try normalizeResponsesRequest(request)
        }

        guard let rawModel = request["model"] as? String, !rawModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.invalidData(L10n.tr("error.proxy_runtime.missing_model"))
        }
        let model = try mapClientModelToUpstream(rawModel)

        guard let messages = request["messages"] as? [Any] else {
            throw AppError.invalidData(L10n.tr("error.proxy_runtime.chat_missing_messages"))
        }

        let downstreamStream = (request["stream"] as? Bool) ?? false

        var input: [[String: Any]] = []
        for raw in messages {
            guard let message = raw as? [String: Any] else {
                throw AppError.invalidData(L10n.tr("error.proxy_runtime.messages_item_must_be_object"))
            }

            guard let role = message["role"] as? String, !role.isEmpty else {
                throw AppError.invalidData(L10n.tr("error.proxy_runtime.message_missing_role"))
            }

            if role == "tool" {
                guard let callID = message["tool_call_id"] as? String, !callID.isEmpty else {
                    throw AppError.invalidData(L10n.tr("error.proxy_runtime.tool_message_missing_call_id"))
                }
                let output = stringifyMessageContent(message["content"])
                input.append([
                    "type": "function_call_output",
                    "call_id": callID,
                    "output": output
                ])
                continue
            }

            let mappedRole: String
            switch role {
            case "system", "developer": mappedRole = "developer"
            case "assistant": mappedRole = "assistant"
            default: mappedRole = "user"
            }

            let contentParts = convertMessageContentToCodexParts(role: role, content: message["content"])
            input.append([
                "type": "message",
                "role": mappedRole,
                "content": contentParts
            ])

            if role == "assistant",
               let toolCalls = message["tool_calls"] as? [Any] {
                for rawToolCall in toolCalls {
                    guard let toolCall = rawToolCall as? [String: Any] else { continue }
                    let toolType = (toolCall["type"] as? String) ?? "function"
                    if toolType != "function" { continue }
                    guard let function = toolCall["function"] as? [String: Any] else { continue }

                    let name = (function["name"] as? String) ?? ""
                    let arguments = stringifyJSONField(function["arguments"])
                    let callID = (toolCall["id"] as? String) ?? ""
                    input.append([
                        "type": "function_call",
                        "call_id": callID,
                        "name": name,
                        "arguments": arguments
                    ])
                }
            }
        }

        let reasoningEffort = (request["reasoning_effort"] as? String)
            ?? (((request["reasoning"] as? [String: Any])?["effort"] as? String) ?? "medium")
        let reasoningSummary = ((request["reasoning"] as? [String: Any])?["summary"] as? String) ?? "auto"
        let reasoning = Self.normalizedReasoningForUpstream([
            "effort": reasoningEffort,
            "summary": reasoningSummary
        ], upstreamModel: model)

        var payload: [String: Any] = [
            "model": model,
            "stream": true,
            "store": false,
            "instructions": "",
            "parallel_tool_calls": (request["parallel_tool_calls"] as? Bool) ?? true,
            "include": ["reasoning.encrypted_content"],
            "reasoning": reasoning,
            "input": input
        ]

        if let tools = request["tools"] as? [Any] {
            var convertedTools: [[String: Any]] = []
            for rawTool in tools {
                guard let tool = rawTool as? [String: Any] else { continue }
                let type = (tool["type"] as? String) ?? ""
                if type == "function",
                   let function = tool["function"] as? [String: Any] {
                    var converted: [String: Any] = ["type": "function"]
                    if let name = function["name"] { converted["name"] = name }
                    if let description = function["description"] { converted["description"] = description }
                    if let parameters = function["parameters"] { converted["parameters"] = parameters }
                    if let strict = function["strict"] { converted["strict"] = strict }
                    convertedTools.append(converted)
                } else {
                    convertedTools.append(tool)
                }
            }
            if !convertedTools.isEmpty {
                payload["tools"] = convertedTools
            }
        }
        if let toolChoice = request["tool_choice"] {
            payload["tool_choice"] = toolChoice
        }

        if let responseFormat = request["response_format"] {
            mapResponseFormat(into: &payload, responseFormat: responseFormat)
        }
        if let text = request["text"] {
            mapTextSettings(into: &payload, text: text)
        }

        return (payload, downstreamStream)
    }

    func convertMessageContentToCodexParts(role: String, content: Any?) -> [[String: Any]] {
        let textType = role == "assistant" ? "output_text" : "input_text"

        guard let content else { return [] }

        if let text = content as? String {
            guard !text.isEmpty else { return [] }
            return [["type": textType, "text": text]]
        }

        guard let items = content as? [Any] else { return [] }
        var parts: [[String: Any]] = []

        for raw in items {
            guard let item = raw as? [String: Any],
                  let type = item["type"] as? String else { continue }

            if type == "text", let text = item["text"] as? String {
                parts.append(["type": textType, "text": text])
                continue
            }

            if type == "image_url",
               let image = item["image_url"] as? [String: Any],
               let url = image["url"] as? String,
               ["user", "developer", "system"].contains(role) {
                parts.append(["type": "input_image", "image_url": url])
                continue
            }
        }

        return parts
    }

    func convertCompletedResponseToChatCompletion(_ response: [String: Any], fallbackModel: String) -> [String: Any] {
        let id = (response["id"] as? String) ?? "chatcmpl_\(UUID().uuidString)"
        let created = (response["created_at"] as? Int) ?? Int(dateProvider.unixSecondsNow())
        let model = normalizeModelForClient((response["model"] as? String) ?? fallbackModel)

        var message: [String: Any] = ["role": "assistant"]
        var reasoningContent: String?
        var textContent: String?
        var toolCalls: [[String: Any]] = []

        if let output = response["output"] as? [Any] {
            for rawItem in output {
                guard let item = rawItem as? [String: Any],
                      let type = item["type"] as? String else { continue }

                switch type {
                case "reasoning":
                    if let summary = item["summary"] as? [Any] {
                        for rawSummary in summary {
                            guard let summaryObject = rawSummary as? [String: Any] else { continue }
                            if (summaryObject["type"] as? String) == "summary_text",
                               let text = summaryObject["text"] as? String,
                               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                reasoningContent = text
                                break
                            }
                        }
                    }
                case "message":
                    if let content = item["content"] as? [Any] {
                        var chunks: [String] = []
                        for rawContent in content {
                            guard let contentObject = rawContent as? [String: Any] else { continue }
                            if (contentObject["type"] as? String) == "output_text",
                               let text = contentObject["text"] as? String,
                               !text.isEmpty {
                                chunks.append(text)
                            }
                        }
                        if !chunks.isEmpty {
                            textContent = chunks.joined()
                        }
                    }
                case "function_call":
                    let callID = (item["call_id"] as? String) ?? ""
                    let name = (item["name"] as? String) ?? ""
                    let arguments = (item["arguments"] as? String) ?? ""
                    toolCalls.append([
                        "id": callID,
                        "type": "function",
                        "function": [
                            "name": name,
                            "arguments": arguments
                        ]
                    ])
                default:
                    break
                }
            }
        }

        if textContent == nil {
            textContent = extractAssistantText(fromCompletedResponse: response)
        }

        message["content"] = textContent ?? NSNull()
        if let reasoningContent {
            message["reasoning_content"] = reasoningContent
        }
        if !toolCalls.isEmpty {
            message["tool_calls"] = toolCalls
        }

        let finishReason = toolCalls.isEmpty ? "stop" : "tool_calls"

        var root: [String: Any] = [
            "id": id,
            "object": "chat.completion",
            "created": created,
            "model": model,
            "choices": [[
                "index": 0,
                "message": message,
                "finish_reason": finishReason,
                "native_finish_reason": finishReason
            ]]
        ]

        if let usage = response["usage"] as? [String: Any] {
            root["usage"] = buildOpenAIUsage(from: usage)
        }

        return root
    }

    // MARK: - Content Serialization Helpers

    func stringifyContent(_ value: Any?) -> String {
        guard let value else { return "" }

        if let text = value as? String {
            return text
        }

        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        return String(describing: value)
    }

    func stringifyMessageContent(_ content: Any?) -> String {
        guard let content else { return "" }

        if let text = content as? String {
            return text
        }

        if let items = content as? [Any] {
            let texts = items.compactMap { item -> String? in
                guard let object = item as? [String: Any] else { return nil }
                return object["text"] as? String
            }
            return texts.joined(separator: "\n")
        }

        if let null = content as? NSNull, null == NSNull() {
            return ""
        }

        if JSONSerialization.isValidJSONObject(content),
           let data = try? JSONSerialization.data(withJSONObject: content),
           let text = String(data: data, encoding: .utf8) {
            return text
        }

        return ""
    }

    func stringifyJSONField(_ value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String {
            return text
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return ""
    }

    func mapResponseFormat(into root: inout [String: Any], responseFormat: Any) {
        guard let formatObject = responseFormat as? [String: Any],
              let formatType = formatObject["type"] as? String else {
            return
        }

        var text = root["text"] as? [String: Any] ?? [:]
        var format = text["format"] as? [String: Any] ?? [:]

        switch formatType {
        case "text":
            format["type"] = "text"
        case "json_schema":
            format["type"] = "json_schema"
            if let schemaObject = formatObject["json_schema"] as? [String: Any] {
                if let name = schemaObject["name"] { format["name"] = name }
                if let strict = schemaObject["strict"] { format["strict"] = strict }
                if let schema = schemaObject["schema"] { format["schema"] = schema }
            }
        default:
            break
        }

        text["format"] = format
        root["text"] = text
    }

    func mapTextSettings(into root: inout [String: Any], text value: Any) {
        guard let textObject = value as? [String: Any],
              let verbosity = textObject["verbosity"] else {
            return
        }

        var target = root["text"] as? [String: Any] ?? [:]
        target["verbosity"] = verbosity
        root["text"] = target
    }

    func extractAssistantText(fromCompletedResponse response: [String: Any]) -> String {
        var segments: [String] = []

        if let outputs = response["output"] as? [Any] {
            for item in outputs {
                guard let object = item as? [String: Any] else { continue }

                if let type = object["type"] as? String, type == "output_text", let text = object["text"] as? String {
                    segments.append(text)
                    continue
                }

                if let messageType = object["type"] as? String, messageType == "message",
                   let content = object["content"] as? [Any] {
                    for part in content {
                        guard let partObj = part as? [String: Any] else { continue }
                        if let text = partObj["text"] as? String {
                            segments.append(text)
                        }
                    }
                }
            }
        }

        if segments.isEmpty, let text = response["output_text"] as? String {
            segments.append(text)
        }

        return segments.joined(separator: "")
    }

    func buildOpenAIUsage(from usage: [String: Any]) -> [String: Any] {
        var root: [String: Any] = [:]
        if let inputTokens = usage["input_tokens"] {
            root["prompt_tokens"] = inputTokens
        }
        if let outputTokens = usage["output_tokens"] {
            root["completion_tokens"] = outputTokens
        }
        if let totalTokens = usage["total_tokens"] {
            root["total_tokens"] = totalTokens
        }
        if let inputDetails = usage["input_tokens_details"] as? [String: Any],
           let cached = inputDetails["cached_tokens"] {
            root["prompt_tokens_details"] = ["cached_tokens": cached]
        }
        if let outputDetails = usage["output_tokens_details"] as? [String: Any],
           let reasoning = outputDetails["reasoning_tokens"] {
            root["completion_tokens_details"] = ["reasoning_tokens": reasoning]
        }
        return root
    }

    func rewriteResponseModelFields(_ value: [String: Any]) -> [String: Any] {
        var output: Any = value
        recurseNormalizeModels(&output)
        return output as? [String: Any] ?? value
    }

    func recurseNormalizeModels(_ any: inout Any) {
        if var dict = any as? [String: Any] {
            for key in dict.keys {
                if key == "model", let model = dict[key] as? String {
                    dict[key] = normalizeModelForClient(model)
                } else if var child = dict[key] {
                    recurseNormalizeModels(&child)
                    dict[key] = child
                }
            }
            any = dict
            return
        }

        if var array = any as? [Any] {
            for index in array.indices {
                var child = array[index]
                recurseNormalizeModels(&child)
                array[index] = child
            }
            any = array
        }
    }
}
