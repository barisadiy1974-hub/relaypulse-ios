import Foundation
import SwiftUI

/// One auto-fix command — same shape as Mac config.js autoFixCommands.
struct FixCommand: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var command: String

    /// What actually runs: `$WATCHED` becomes the "What counts as up" service
    /// list, so the default commands act on nginx or docker as readily as on a
    /// relay. The names are already filtered to systemd-safe characters.
    var script: String { command.replacingOccurrences(of: "$WATCHED", with: WatchTargets.servicesString) }
}

/// AI / auto-fix settings. Keys live in Keychain; everything else in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    // NOTE: @AppStorage is NOT used here. It is a View property wrapper and does not
    // fire objectWillChange inside ObservableObject, so the provider check was stale.
    @Published var aiProvider: String = UserDefaults.standard.string(forKey: "aiProvider") ?? "openai" {
        didSet { UserDefaults.standard.set(aiProvider, forKey: "aiProvider") }
    }
    @Published var dryRun: Bool = UserDefaults.standard.object(forKey: "autoFixDryRun") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dryRun, forKey: "autoFixDryRun") }
    }

    @Published var openaiKey: String = Keychain.get("openaiApiKey") {
        didSet { Keychain.set(openaiKey, for: "openaiApiKey") }
    }
    @Published var claudeKey: String = Keychain.get("claudeApiKey") {
        didSet { Keychain.set(claudeKey, for: "claudeApiKey") }
    }
    /// Identity-linked Anthropic keys return 400 without `anthropic-workspace-id`.
    /// Not a secret — just an identifier — so UserDefaults is fine.
    @Published var claudeWorkspaceId: String = UserDefaults.standard.string(forKey: "claudeWorkspaceId") ?? "" {
        didSet { UserDefaults.standard.set(claudeWorkspaceId, forKey: "claudeWorkspaceId") }
    }

    @Published var commands: [FixCommand] = AppSettings.loadCommands() {
        didSet { AppSettings.saveCommands(commands) }
    }

    var activeKey: String { aiProvider == "claude" ? claudeKey : openaiKey }
    var hasKey: Bool { !activeKey.isEmpty }
    var providerLabel: String { aiProvider == "claude" ? "Claude" : "OpenAI" }
    var modelLabel: String { aiProvider == "claude" ? "claude-haiku-4-5" : "gpt-4o-mini" }

    /// Returns the other provider's name if the active key prefix doesn't match the selected provider.
    /// Anthropic keys start with "sk-ant-", OpenAI keys with "sk-".
    var keyBelongsToOtherProvider: String? {
        let k = activeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return nil }
        if aiProvider == "openai" && k.hasPrefix("sk-ant-") { return "claude" }
        if aiProvider == "claude" && k.hasPrefix("sk-") && !k.hasPrefix("sk-ant-") { return "openai" }
        return nil
    }

    // MARK: - Command persistence

    private static let cmdKey = "autoFixCommands"

    static func loadCommands() -> [FixCommand] {
        if let data = UserDefaults.standard.data(forKey: cmdKey),
           let list = try? JSONDecoder().decode([FixCommand].self, from: data),
           !list.isEmpty {
            // Untouched old defaults (relay-only service names) become the
            // watch-list versions; anything the operator edited stays as is.
            return list.map { c in
                guard legacyDefaults[c.id] == c.command,
                      let fresh = defaultCommands.first(where: { $0.id == c.id }) else { return c }
                return fresh
            }
        }
        return defaultCommands
    }

    static func saveCommands(_ list: [FixCommand]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: cmdKey)
        }
    }

    func resetCommands() { commands = AppSettings.defaultCommands }

    /// At first launch, reads `Documents/ai_key.json`, stores the key in Keychain, and deletes the file.
    /// Used to seed the key from Mac via `devicectl device copy to` — no manual entry needed.
    /// Expected format: {"provider":"claude","key":"sk-ant-…","workspaceId":""}
    func importSeedKeyIfPresent() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = dir.appendingPathComponent("ai_key.json")
        guard let data = try? Data(contentsOf: f),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = (o["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return }
        let provider = (o["provider"] as? String) ?? (key.hasPrefix("sk-ant-") ? "claude" : "openai")
        if provider == "claude" { claudeKey = key } else { openaiKey = key }
        claudeWorkspaceId = (o["workspaceId"] as? String) ?? ""
        aiProvider = provider
        try? FileManager.default.removeItem(at: f)
        NSLog("AppSettings: AI key seeded from file (provider=\(provider))")
    }

    /// The relay-only versions these ids shipped with (same as Mac
    /// src/config.js), recognised so they can be upgraded in place.
    static let legacyDefaults: [Int: String] = [
        1: "for svc in anon anon@default anyone anyone-relay tor-anon; do systemctl cat \"$svc\" >/dev/null 2>&1 && systemctl restart \"$svc\" && echo \"restarted: $svc\" && break; done",
        2: "for svc in anon anon@default anyone anyone-relay tor-anon; do s=$(systemctl is-active \"$svc\" 2>/dev/null); [ -n \"$s\" ] && echo \"$svc=$s\"; done",
        3: "journalctl -u anon -n 50 --no-pager 2>/dev/null || journalctl -u anyone-relay -n 50 --no-pager 2>/dev/null || echo \"(log not found)\"",
    ]

    /// `$WATCHED` = the "What counts as up" services (default: the relay units
    /// the app always used, so a relay fleet runs exactly what it ran before).
    static let defaultCommands: [FixCommand] = [
        .init(id: 1, name: "Restart watched service",
              command: "for svc in $WATCHED; do systemctl cat \"$svc\" >/dev/null 2>&1 && systemctl restart \"$svc\" && echo \"restarted: $svc\" && break; done"),
        .init(id: 2, name: "Watched service status",
              command: "for svc in $WATCHED; do s=$(systemctl is-active \"$svc\" 2>/dev/null); [ -n \"$s\" ] && echo \"$svc=$s\"; done"),
        .init(id: 3, name: "Last 50 log lines",
              command: "for svc in $WATCHED; do systemctl cat \"$svc\" >/dev/null 2>&1 && { journalctl -u \"$svc\" -u \"$svc@*\" -n 50 --no-pager; exit 0; }; done; echo \"(log not found)\""),
        .init(id: 5, name: "Restart SSH service",
              command: "systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; echo \"ssh=$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null)\""),
        .init(id: 12, name: "Disk usage",
              command: "df -h / /var /tmp 2>/dev/null"),
        .init(id: 13, name: "RAM and load",
              command: "free -m 2>/dev/null || vm_stat; uptime"),
        .init(id: 16, name: "Reboot required?",
              command: "[ -f /var/run/reboot-required ] && cat /var/run/reboot-required || echo \"no reboot needed\""),
    ]
}
