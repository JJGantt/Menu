import Foundation

enum AnthropicError: LocalizedError {
    case noAPIKey
    case requestFailed(String)
    case decodeFailed
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "No API key set. Open Settings to add one."
        case .requestFailed(let s): return "Request failed: \(s)"
        case .decodeFailed: return "Couldn't read response."
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        }
    }
}

/// Tool the model can call. The handler is async and returns a string result that
/// gets fed back as a `tool_result` content block.
struct AnthropicTool {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    let handler: (_ input: [String: Any]) async throws -> String
}

struct AnthropicClient {
    static var model: String { AIModel.current.rawValue }
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2023-06-01"

    // MARK: - General multi-turn with optional tools

    static func chatWithTools(question: String,
                              history: [ChatTurn],
                              systemStable: String,
                              systemDynamic: String,
                              tools: [AnthropicTool],
                              interactionId: UUID,
                              sessionId: String?,
                              finishAfterTools: Bool = false,
                              model: String? = nil,
                              onActivity: (@MainActor (String?) -> Void)? = nil) async throws -> ChatTurn {
        guard let apiKey = APIKeyStore.current, APIKeyStore.looksValid(apiKey) else {
            throw AnthropicError.noAPIKey
        }

        // Prior turns go back WITH the tools they called, as real tool_use/tool_result blocks. Sent as
        // question/answer text alone, the model reads a run of its own "Added X" answers with no tool
        // behind them and starts answering "Added" without calling anything.
        var messages: [[String: Any]] = []
        for turn in history { messages += turn.messages }
        messages.append(["role": "user", "content": question])
        var traces: [ToolTrace] = []

        // Loop: send → if tool_use, run handlers, append results, send again.
        // Cap at a reasonable number of turns to avoid infinite loops.
        var collectedText: [String] = []
        for _ in 0..<6 {
            let started = Date()
            let response: CallResponse
            do {
                response = try await call(apiKey: apiKey, systemStable: systemStable, systemDynamic: systemDynamic, tools: tools, messages: messages, model: model)
            } catch {
                let latency = Int(Date().timeIntervalSince(started) * 1000)
                await AppLogger.shared.record(.init(
                    timestamp: started, interactionId: interactionId, sessionId: sessionId,
                    backend: "api", kind: "api_error", toolName: nil, input: nil, output: nil,
                    error: error.localizedDescription, latencyMs: latency,
                    tokensIn: nil, tokensOut: nil, userInput: nil, finalAnswer: nil))
                throw error
            }
            let latency = Int(Date().timeIntervalSince(started) * 1000)
            await AppLogger.shared.record(.init(
                timestamp: started, interactionId: interactionId, sessionId: sessionId,
                backend: "api", kind: "api_request", toolName: nil, input: nil,
                output: response.stopReason, error: nil, latencyMs: latency,
                tokensIn: response.tokensIn, tokensOut: response.tokensOut,
                userInput: nil, finalAnswer: nil))

            // Capture any plain-text blocks before/after tool_use.
            for block in response.content {
                if let type = block["type"] as? String, type == "text",
                   let text = block["text"] as? String, !text.isEmpty {
                    collectedText.append(text)
                }
            }

            if response.stopReason != "tool_use" {
                break
            }

            // Append assistant message verbatim (must include the tool_use blocks).
            messages.append(["role": "assistant", "content": response.content])

            // Run each tool_use block and collect tool_result blocks.
            var toolResults: [[String: Any]] = []
            for block in response.content {
                guard let type = block["type"] as? String, type == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String else { continue }
                let input = (block["input"] as? [String: Any]) ?? [:]

                // Surface to UI before executing.
                if let onActivity {
                    let inputJSON = (try? String(data: JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted]), encoding: .utf8)) ?? "{}"
                    let activity = "\(name)(\(inputJSON))"
                    await MainActor.run { onActivity(activity) }
                }

                let toolStart = Date()
                let resultText: String
                let isError: Bool
                var toolError: String?
                if let tool = tools.first(where: { $0.name == name }) {
                    do {
                        resultText = try await tool.handler(input)
                        isError = false
                    } catch {
                        resultText = "Tool error: \(error.localizedDescription)"
                        toolError = error.localizedDescription
                        isError = true
                    }
                } else {
                    resultText = "Unknown tool: \(name)"
                    toolError = "Unknown tool"
                    isError = true
                }
                let toolLatency = Int(Date().timeIntervalSince(toolStart) * 1000)
                await AppLogger.shared.record(.init(
                    timestamp: toolStart, interactionId: interactionId, sessionId: sessionId,
                    backend: "api", kind: isError ? "tool_error" : "tool_call", toolName: name,
                    input: input, output: resultText, error: toolError, latencyMs: toolLatency,
                    tokensIn: nil, tokensOut: nil, userInput: nil, finalAnswer: nil))

                let inputJSON = (try? String(data: JSONSerialization.data(withJSONObject: input), encoding: .utf8)) ?? "{}"
                traces.append(ToolTrace(id: id, name: name, inputJSON: inputJSON, result: resultText, isError: isError))
                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": id,
                    "content": resultText,
                    "is_error": isError
                ])
            }
            messages.append(["role": "user", "content": toolResults])
            // `finishAfterTools`: the tools ARE the answer (the order list), so once they have all
            // succeeded there is nothing for another round trip to say. A failed one goes back to the
            // model to be fixed.
            if finishAfterTools && !toolResults.contains(where: { $0["is_error"] as? Bool == true }) { break }
        }
        // Clear activity once we're returning the final answer.
        if let onActivity {
            await MainActor.run { onActivity(nil) }
        }
        let answer = collectedText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatTurn(question: question, answer: answer, tools: traces)
    }

    // MARK: - Single API call

    private struct CallResponse {
        let content: [[String: Any]]
        let stopReason: String?
        let tokensIn: Int?
        let tokensOut: Int?
    }

    private static func call(apiKey: String,
                             systemStable: String,
                             systemDynamic: String,
                             tools: [AnthropicTool],
                             messages: [[String: Any]],
                             model: String?) async throws -> CallResponse {
        // Split system into two blocks: stable prefix (cached) + dynamic suffix.
        // Cache hits drop input token rate-limit cost dramatically.
        let systemBlocks: [[String: Any]] = [
            [
                "type": "text",
                "text": systemStable,
                "cache_control": ["type": "ephemeral", "ttl": "1h"]   // 1-hour cache (vs 5-min default)
            ],
            [
                "type": "text",
                "text": systemDynamic
            ]
        ]
        var body: [String: Any] = [
            "model": model ?? Self.model,
            "max_tokens": 4096,
            "system": systemBlocks,
            "messages": messages
        ]
        // A model named by the caller (the order passes) takes its own thinking settings.
        let params = model.map { AIModel(rawValue: $0)?.thinkingParams ?? [:] } ?? AIModel.current.thinkingParams
        for (k, v) in params { body[k] = v }
        if !tools.isEmpty {
            body["tools"] = tools.map { tool in
                [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": tool.inputSchema
                ] as [String: Any]
            }
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(version, forHTTPHeaderField: "anthropic-version")
        req.setValue("extended-cache-ttl-2025-04-11", forHTTPHeaderField: "anthropic-beta")  // enables ttl:1h
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AnthropicError.requestFailed("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "?"
            throw AnthropicError.httpError(http.statusCode, msg)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AnthropicError.decodeFailed
        }
        let usage = json["usage"] as? [String: Any]
        return CallResponse(
            content: content,
            stopReason: json["stop_reason"] as? String,
            tokensIn: usage?["input_tokens"] as? Int,
            tokensOut: usage?["output_tokens"] as? Int
        )
    }
}

/// One question and its answer, with every tool the answer called. Kept in chat history so the next
/// request shows the model what it actually did, not only what it said.
struct ChatTurn: Codable {
    let question: String
    let answer: String
    var tools: [ToolTrace] = []

    /// A long tool result (a menu section) is cut in history: the call and its outcome are what
    /// matter later, and the model can call again for the detail.
    private static let resultLimit = 400

    /// The turn as API messages: question, the tool calls and their results, then the answer.
    var messages: [[String: Any]] {
        var out: [[String: Any]] = [["role": "user", "content": question]]
        if !tools.isEmpty {
            out.append(["role": "assistant", "content": tools.map { t -> [String: Any] in
                let input = (try? JSONSerialization.jsonObject(with: Data(t.inputJSON.utf8))) ?? [String: Any]()
                return ["type": "tool_use", "id": t.id, "name": t.name, "input": input]
            }])
            out.append(["role": "user", "content": tools.map { t -> [String: Any] in
                let r = t.result.count > Self.resultLimit ? String(t.result.prefix(Self.resultLimit)) + "…" : t.result
                return ["type": "tool_result", "tool_use_id": t.id, "content": r, "is_error": t.isError]
            }])
        }
        out.append(["role": "assistant", "content": answer.isEmpty ? "(no answer)" : answer])
        return out
    }
}

struct ToolTrace: Codable {
    let id: String
    let name: String
    let inputJSON: String
    let result: String
    let isError: Bool
}
