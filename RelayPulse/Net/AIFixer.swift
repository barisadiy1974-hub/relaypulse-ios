import Foundation

/// AI diagnosis — iOS counterpart to Mac src/ai-fixer.js.
/// Sends the relay's error and recent logs to the model, which picks a fix command.
/// The command is NOT executed here; the caller shows it to the user first.
enum AIFixer {
    struct Suggestion {
        var commandId: Int?
        var reason: String
        var raw: String
    }

    enum AIError: LocalizedError {
        case noKey
        case http(Int, String)
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .noKey: return "No API key configured"
            // The raw body was shown before ("API 401: {\"error\":...") — say what to do.
            case .http(401, _), .http(403, _):
                return "The AI provider refused the API key. Check it under Tools › AI API key and commands."
            case .http(429, _):
                return "The AI provider is rate-limiting this key, or the account has no credit left. Try again later or check the account."
            case .http(let c, let b): return "API \(c): \(b.prefix(200))"
            case .badResponse(let m): return "Could not read response: \(m)"
            }
        }
    }

    // MARK: - Key test

    /// Validates the key with a minimal request. Returns the model name on success.
    static func testKey(provider: String, key: String, workspaceId: String = "") async throws -> String {
        guard !key.isEmpty else { throw AIError.noKey }
        let reply = try await call(provider: provider, key: key, workspaceId: workspaceId,
                                   prompt: "Reply with only the word OK, nothing else.",
                                   maxTokens: 8)
        let model = provider == "claude" ? "claude-haiku-4-5" : "gpt-4o-mini"
        return "\(model) → \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
    }

    // MARK: - Diagnosis

    static func analyze(server: Server, errorMessage: String, logs: String,
                        commands: [FixCommand], provider: String, key: String,
                        workspaceId: String = "") async throws -> Suggestion {
        guard !key.isEmpty else { throw AIError.noKey }
        let list = commands.map { "id=\($0.id) name=\"\($0.name)\"" }.joined(separator: "\n")
        let prompt = """
        You are a Linux server management assistant. The server may run anything — a web or
        database server, containers, or an Anyone/Tor relay; tell which from the logs.
        Reply ONLY with JSON, nothing else.

        Server: \(server.name) (\(server.host))
        Error report: \(errorMessage.prefix(500))

        Recent log lines (read carefully — find the root cause here):
        \(logs.suffix(6000))

        DECISION RULES:
        1. READ THE LOGS FIRST — identify the cause from logs, don't just restart blindly.
        2. If disk is full, pick the disk command.
        3. If "Address already in use", pick a command that stops the process and restarts.
        4. If there is a config error, pick a log/status check command first.
        5. If the service is down with no specific log error, pick the restart command.
        - ONLY pick an id that ACTUALLY EXISTS in the list below; do not invent one.
        - If unsure, pick the log command.

        Available commands:
        \(list)

        Response format (JSON ONLY):
        {"commandId": <number or null>, "reason": "<root cause and why this command, 1-2 sentences>"}
        """
        let text = try await call(provider: provider, key: key, workspaceId: workspaceId,
                                  prompt: prompt, maxTokens: 500)
        return parse(text)
    }

    private static func parse(_ text: String) -> Suggestion {
        // Model sometimes wraps JSON in ``` or adds prose before it.
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return Suggestion(commandId: nil, reason: text.trimmingCharacters(in: .whitespacesAndNewlines), raw: text)
        }
        let json = String(text[start...end])
        guard let d = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return Suggestion(commandId: nil, reason: json, raw: text)
        }
        let id = obj["commandId"] as? Int
        let reason = (obj["reason"] as? String) ?? ""
        return Suggestion(commandId: id, reason: reason, raw: text)
    }

    // MARK: - Providers

    private static func call(provider: String, key: String, workspaceId: String,
                             prompt: String, maxTokens: Int) async throws -> String {
        provider == "claude"
            ? try await claude(key: key, workspaceId: workspaceId, prompt: prompt, maxTokens: maxTokens)
            : try await openAI(key: key, prompt: prompt, maxTokens: maxTokens)
    }

    private static func openAI(key: String, prompt: String, maxTokens: Int) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 45
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini",
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]],
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = o["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw AIError.badResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return content
    }

    private static func claude(key: String, workspaceId: String, prompt: String, maxTokens: Int) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Identity-linked keys return 400 without this header.
        let ws = workspaceId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !ws.isEmpty { req.setValue(ws, forHTTPHeaderField: "anthropic-workspace-id") }
        req.timeoutInterval = 45
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5",
            "max_tokens": maxTokens,
            "messages": [["role": "user", "content": prompt]],
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try check(resp, data)
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = o["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AIError.badResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
        return text
    }

    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        throw AIError.http(http.statusCode, String(decoding: data, as: UTF8.self))
    }
}
