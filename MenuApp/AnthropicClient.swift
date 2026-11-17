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
                              onActivity: (@MainActor (String?) -> Void)? = nil,
                              onText: (@MainActor (String) -> Void)? = nil) async throws -> ChatTurn {
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
        // The answer so far, as `collectedText` will join it, handed to `onText` as each piece streams in.
        var shown = ""
        let streamText: ((String) async -> Void)? = onText.map { onText in
            { piece in
                shown += piece
                let snapshot = (collectedText + [shown]).joined(separator: "\n")
                await MainActor.run { onText(snapshot) }
            }
        }
        for _ in 0..<6 {
            shown = ""
            let started = Date()
            let response: CallResponse
            do {
                response = try await call(apiKey: apiKey, systemStable: systemStable, systemDynamic: systemDynamic, tools: tools, messages: messages, model: model, onText: streamText)
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
                             model: String?,
                             onText: ((String) async -> Void)?) async throws -> CallResponse {
        // Split system into two blocks: stable prefix (cached) + dynamic suffix.
        // The default 5-minute cache, not the 1-hour one: questions come in with long gaps, so most
        // first calls write the cache, and a 1-hour write costs 2x the input price where a 5-minute
        // write costs 1.25x. Five minutes still covers the tool round trips within one question
        // and quick follow-ups, which read it at 0.05x.
        let systemBlocks: [[String: Any]] = [
            [
                "type": "text",
                "text": systemStable,
                "cache_control": ["type": "ephemeral"]
            ],
            [
                "type": "text",
                "text": systemDynamic
            ]
        ]
        var body: [String: Any] = [
            "model": model ?? Self.model,
            "max_tokens": 4096,
            "stream": true,
            "system": systemBlocks,
            "messages": messages
        ]
        // A model named by the caller (the order passes) takes its own settings.
        let params = model.map { AIModel(rawValue: $0)?.requestParams ?? [:] } ?? AIModel.current.requestParams
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
        do {
            return try await stream(apiKey: apiKey, body: body, onText: onText)
        } catch AnthropicError.httpError(429, _) where body["speed"] != nil {
            // Fast mode has its own rate limit; at standard speed the same request still goes through.
            body.removeValue(forKey: "speed")
            return try await stream(apiKey: apiKey, body: body, onText: onText)
        }
    }

    /// One streamed request. The response is rebuilt block by block from its events — the same content
    /// a non-streamed request returns, thinking signatures included, so it can be sent back verbatim —
    /// and each text delta is handed to `onText` as it arrives.
    private static func stream(apiKey: String,
                               body: [String: Any],
                               onText: ((String) async -> Void)?) async throws -> CallResponse {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue(version, forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AnthropicError.requestFailed("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await b in bytes { data.append(b) }
            throw AnthropicError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "?")
        }

        var content: [[String: Any]] = []
        var current: [String: Any] = [:]
        var partialJSON = ""
        var stopReason: String?
        var tokensIn: Int?
        var tokensOut: Int?
        for try await line in bytes.lines {
            guard line.hasPrefix("data:"),
                  let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "message_start":
                let usage = (event["message"] as? [String: Any])?["usage"] as? [String: Any]
                tokensIn = usage?["input_tokens"] as? Int
            case "content_block_start":
                current = event["content_block"] as? [String: Any] ?? [:]
                partialJSON = ""
            case "content_block_delta":
                guard let delta = event["delta"] as? [String: Any] else { break }
                switch delta["type"] as? String {
                case "text_delta":
                    let piece = delta["text"] as? String ?? ""
                    current["text"] = (current["text"] as? String ?? "") + piece
                    if let onText, !piece.isEmpty { await onText(piece) }
                case "input_json_delta":
                    partialJSON += delta["partial_json"] as? String ?? ""
                case "thinking_delta":
                    current["thinking"] = (current["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    current["signature"] = delta["signature"]
                default: break
                }
            case "content_block_stop":
                if current["type"] as? String == "tool_use" {
                    current["input"] = partialJSON.isEmpty
                        ? [String: Any]()
                        : (try? JSONSerialization.jsonObject(with: Data(partialJSON.utf8))) ?? [String: Any]()
                }
                content.append(current)
                current = [:]
            case "message_delta":
                stopReason = (event["delta"] as? [String: Any])?["stop_reason"] as? String ?? stopReason
                tokensOut = (event["usage"] as? [String: Any])?["output_tokens"] as? Int ?? tokensOut
            case "error":
                let err = event["error"] as? [String: Any]
                throw AnthropicError.requestFailed(err?["message"] as? String ?? "stream error")
            default: break
            }
        }
        guard stopReason != nil else { throw AnthropicError.decodeFailed }
        return CallResponse(content: content, stopReason: stopReason, tokensIn: tokensIn, tokensOut: tokensOut)
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
