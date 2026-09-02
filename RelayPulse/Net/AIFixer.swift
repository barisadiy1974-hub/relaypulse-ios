import Foundation

/// AI teşhis — Mac src/ai-fixer.js'in iPhone karşılığı.
/// Relay'in hatasını + son loglarını modele gönderir, komut listesinden birini seçtirir.
/// Komut BURADA çalıştırılmaz; çağıran taraf kullanıcıya sorup çalıştırır.
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
            case .noKey: return "API anahtarı girilmedi"
            case .http(let c, let b): return "API \(c): \(b.prefix(200))"
            case .badResponse(let m): return "Yanıt okunamadı: \(m)"
            }
        }
    }

    // MARK: - Anahtar testi

    /// Anahtarı en ucuz istekle doğrular. Başarılıysa modelin adını döner.
    static func testKey(provider: String, key: String) async throws -> String {
        guard !key.isEmpty else { throw AIError.noKey }
        let reply = try await call(provider: provider, key: key,
                                   prompt: "Sadece OK yaz, baska hicbir sey yazma.",
                                   maxTokens: 8)
        let model = provider == "claude" ? "claude-haiku-4-5" : "gpt-4o-mini"
        return "\(model) → \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
    }

    // MARK: - Teşhis

    static func analyze(server: Server, errorMessage: String, logs: String,
                        commands: [FixCommand], provider: String, key: String) async throws -> Suggestion {
        guard !key.isEmpty else { throw AIError.noKey }
        let list = commands.map { "id=\($0.id) ad=\"\($0.name)\"" }.joined(separator: "\n")
        let prompt = """
        Sen bir Linux sunucu yonetim asistanisin. Anyone Network relay sunucularini izliyorsun.
        Sadece JSON ile cevap ver, baska hicbir sey yazma.

        Sunucu: \(server.name) (\(server.host))
        Hata bildirimi: \(errorMessage.prefix(500))

        Son log satirlari (DIKKATLI OKU — asil nedeni buradan bul):
        \(logs.suffix(6000))

        KARAR KURALLARI:
        1. ONCE LOGLARI OKU — nedeni logdan tespit et, koru restart yapma.
        2. Disk dolu ise disk komutunu sec.
        3. "Address already in use" varsa sureci durdurup yeniden baslatan komutu sec.
        4. Konfigurasyon hatasi varsa once log/durum kontrol komutunu sec.
        5. Servis down ve logda spesifik hata yoksa restart komutunu sec.
        - SADECE asagidaki listede GERCEKTEN VAR OLAN bir id sec; uydurma.
        - Emin degilsen log komutunu sec.

        Kullanilabilir komutlar:
        \(list)

        Yanit formati (SADECE JSON):
        {"commandId": <sayi veya null>, "reason": "<asil neden ve neden bu komut, 1-2 cumle>"}
        """
        let text = try await call(provider: provider, key: key, prompt: prompt, maxTokens: 500)
        return parse(text)
    }

    private static func parse(_ text: String) -> Suggestion {
        // Model bazen JSON'u ``` icine sarar ya da once aciklama yazar.
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

    // MARK: - Sağlayıcılar

    private static func call(provider: String, key: String, prompt: String, maxTokens: Int) async throws -> String {
        provider == "claude"
            ? try await claude(key: key, prompt: prompt, maxTokens: maxTokens)
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

    private static func claude(key: String, prompt: String, maxTokens: Int) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        guard let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        throw AIError.http((resp as! HTTPURLResponse).statusCode,
                           String(decoding: data, as: UTF8.self))
    }
}
