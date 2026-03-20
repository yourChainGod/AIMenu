import Foundation

// MARK: - SSE Types

struct SSEEvent {
    var event: String?
    var data: String
}

struct ChatStreamState {
    var responseID: String
    var createdAt: Int
    var model: String
    var functionCallIndex: Int
    var hasReceivedArgumentsDelta: Bool
    var hasToolCallAnnounced: Bool
}

// MARK: - SSE Parsing & Stream Conversion

extension SwiftNativeProxyRuntimeService {
    func parseSSEEvents(from data: Data) -> [SSEEvent] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")

        return normalized
            .components(separatedBy: "\n\n")
            .compactMap { block in
                if block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return nil
                }

                var eventName: String?
                var dataLines: [String] = []
                for line in block.components(separatedBy: "\n") {
                    if line.hasPrefix("event:") {
                        eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("data:") {
                        dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
                    }
                }

                let joinedData = dataLines.joined(separator: "\n")
                return joinedData.isEmpty ? nil : SSEEvent(event: eventName, data: joinedData)
            }
    }

    func extractCompletedResponse(fromSSE data: Data) throws -> [String: Any] {
        let events = parseSSEEvents(from: data)
        var lastJSON: [String: Any]?

        for event in events {
            guard event.data != "[DONE]" else { continue }
            guard let payloadData = event.data.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                continue
            }

            lastJSON = object

            if (object["type"] as? String) == "response.completed",
               let response = object["response"] as? [String: Any] {
                return response
            }

            if object["id"] != nil, object["output"] != nil {
                return object
            }

            if (object["type"] as? String) == "response.error" {
                let message = (object["error"] as? [String: Any])?["message"] as? String ?? L10n.tr("error.proxy_runtime.upstream_response_error")
                throw AppError.network(message)
            }
        }

        // 仅当 lastJSON 具备已知有效结构时才回退，避免将心跳/空事件误判为响应
        if let lastJSON,
           lastJSON["id"] != nil || lastJSON["output"] != nil || lastJSON["choices"] != nil {
            return lastJSON
        }

        throw AppError.network(L10n.tr("error.proxy_runtime.sse_extract_completed_failed"))
    }

    func convertResponsesSSEToChatCompletionsSSE(_ sseData: Data, fallbackModel: String) throws -> Data {
        let events = parseSSEEvents(from: sseData)
        // functionCallIndex 从 -1 开始：每次遇到新 tool_call 先 += 1 再使用，
        // 第一个 tool_call 的 index 为 0，语义与 OpenAI Chat Completions 保持一致。
        var state = ChatStreamState(
            responseID: "chatcmpl_\(UUID().uuidString)",
            createdAt: Int(dateProvider.unixSecondsNow()),
            model: normalizeModelForClient(fallbackModel),
            functionCallIndex: -1,
            hasReceivedArgumentsDelta: false,
            hasToolCallAnnounced: false
        )

        var lines = ""
        for event in events {
            let chunks = translateSSEEventToChatChunks(event, state: &state)
            for chunk in chunks {
                lines += "data: \(jsonString(chunk))\n\n"
            }
        }

        lines += "data: [DONE]\n\n"
        return Data(lines.utf8)
    }

    func translateSSEEventToChatChunks(_ event: SSEEvent, state: inout ChatStreamState) -> [[String: Any]] {
        guard event.data != "[DONE]",
              let payloadData = event.data.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let kind = parsed["type"] as? String else {
            return []
        }

        switch kind {
        case "response.created":
            if let response = parsed["response"] as? [String: Any] {
                state.responseID = (response["id"] as? String) ?? state.responseID
                state.createdAt = (response["created_at"] as? Int) ?? state.createdAt
                state.model = normalizeModelForClient((response["model"] as? String) ?? state.model)
            }
            return []

        case "response.reasoning_summary_text.delta":
            let delta = (parsed["delta"] as? String) ?? ""
            guard !delta.isEmpty else { return [] }
            return [
                buildChatChunk(
                    state: state,
                    delta: ["role": "assistant", "reasoning_content": delta],
                    finishReason: nil,
                    usage: ((parsed["response"] as? [String: Any])?["usage"] as? [String: Any])
                )
            ]

        case "response.reasoning_summary_text.done":
            return [
                buildChatChunk(
                    state: state,
                    delta: ["role": "assistant", "reasoning_content": "\n\n"],
                    finishReason: nil,
                    usage: ((parsed["response"] as? [String: Any])?["usage"] as? [String: Any])
                )
            ]

        case "response.output_text.delta":
            let delta = (parsed["delta"] as? String) ?? ""
            guard !delta.isEmpty else { return [] }
            return [
                buildChatChunk(
                    state: state,
                    delta: ["role": "assistant", "content": delta],
                    finishReason: nil,
                    usage: ((parsed["response"] as? [String: Any])?["usage"] as? [String: Any])
                )
            ]

        case "response.output_item.added":
            guard let item = parsed["item"] as? [String: Any],
                  (item["type"] as? String) == "function_call" else {
                return []
            }
            state.functionCallIndex += 1
            state.hasReceivedArgumentsDelta = false
            state.hasToolCallAnnounced = true
            return [
                buildChatChunk(
                    state: state,
                    delta: [
                        "role": "assistant",
                        "tool_calls": [[
                            "index": state.functionCallIndex,
                            "id": (item["call_id"] as? String) ?? "",
                            "type": "function",
                            "function": [
                                "name": (item["name"] as? String) ?? "",
                                "arguments": ""
                            ]
                        ]]
                    ],
                    finishReason: nil,
                    usage: ((parsed["response"] as? [String: Any])?["usage"] as? [String: Any])
                )
            ]

        case "response.function_call_arguments.delta":
            state.hasReceivedArgumentsDelta = true
            return [
                buildChatChunk(
                    state: state,
                    delta: [
                        "tool_calls": [[
                            "index": state.functionCallIndex,
                            "function": [
                                "arguments": (parsed["delta"] as? String) ?? ""
                            ]
                        ]]
                    ],
                    finishReason: nil,
                    usage: ((parsed["response"] as? [String: Any])?["usage"] as? [String: Any])
                )
            ]

        case "response.function_call_arguments.done":
            if state.hasReceivedArgumentsDelta {
                return []
            }
            return [
                buildChatChunk(
                    state: state,
                    delta: [
                        "tool_calls": [[
                            "index": state.functionCallIndex,
                            "function": [
                                "arguments": (parsed["arguments"] as? String) ?? ""
                            ]
                        ]]
                    ],
                    finishReason: nil,
                    usage: ((parsed["response"] as? [String: Any])?["usage"] as? [String: Any])
                )
            ]

        case "response.output_item.done":
            guard let item = parsed["item"] as? [String: Any],
                  (item["type"] as? String) == "function_call" else {
                return []
            }

            if state.hasToolCallAnnounced {
                state.hasToolCallAnnounced = false
                return []
            }

            state.functionCallIndex += 1
            return [
                buildChatChunk(
                    state: state,
                    delta: [
                        "role": "assistant",
                        "tool_calls": [[
                            "index": state.functionCallIndex,
                            "id": (item["call_id"] as? String) ?? "",
                            "type": "function",
                            "function": [
                                "name": (item["name"] as? String) ?? "",
                                "arguments": (item["arguments"] as? String) ?? ""
                            ]
                        ]]
                    ],
                    finishReason: nil,
                    usage: ((parsed["response"] as? [String: Any])?["usage"] as? [String: Any])
                )
            ]

        case "response.completed":
            let finishReason = state.functionCallIndex >= 0 ? "tool_calls" : "stop"
            return [
                buildChatChunk(
                    state: state,
                    delta: [:],
                    finishReason: finishReason,
                    usage: ((parsed["response"] as? [String: Any])?["usage"] as? [String: Any])
                )
            ]

        default:
            return []
        }
    }

    func buildChatChunk(
        state: ChatStreamState,
        delta: [String: Any],
        finishReason: String?,
        usage: [String: Any]?
    ) -> [String: Any] {
        let finishValue: Any = finishReason ?? NSNull()
        var chunk: [String: Any] = [
            "id": state.responseID,
            "object": "chat.completion.chunk",
            "created": max(0, state.createdAt),
            "model": state.model,
            "choices": [[
                "index": 0,
                "delta": delta,
                "finish_reason": finishValue,
                "native_finish_reason": finishValue
            ]]
        ]

        if let usage {
            chunk["usage"] = buildOpenAIUsage(from: usage)
        }

        return chunk
    }
}
