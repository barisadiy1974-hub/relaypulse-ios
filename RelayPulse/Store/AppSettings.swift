import Foundation
import SwiftUI

/// Bir auto-fix komutu — Mac config.js autoFixCommands ile aynı şekil.
struct FixCommand: Codable, Identifiable, Hashable {
    var id: Int
    var name: String
    var command: String
}

/// AI / auto-fix ayarları. Anahtarlar Keychain'de, gerisi UserDefaults'ta.
@MainActor
final class AppSettings: ObservableObject {
    // NOT: @AppStorage burada KULLANILMAZ. O bir View property wrapper'i;
    // ObservableObject icinde objectWillChange tetiklemiyor -> saglayici
    // degistiginde ekran yenilenmiyor, "anahtar var mi" kontrolu bayat kaliyordu.
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

    @Published var commands: [FixCommand] = AppSettings.loadCommands() {
        didSet { AppSettings.saveCommands(commands) }
    }

    var activeKey: String { aiProvider == "claude" ? claudeKey : openaiKey }
    var hasKey: Bool { !activeKey.isEmpty }

    // MARK: - Komut listesi kalıcılığı

    private static let cmdKey = "autoFixCommands"

    static func loadCommands() -> [FixCommand] {
        if let data = UserDefaults.standard.data(forKey: cmdKey),
           let list = try? JSONDecoder().decode([FixCommand].self, from: data),
           !list.isEmpty {
            return list
        }
        return defaultCommands
    }

    static func saveCommands(_ list: [FixCommand]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: cmdKey)
        }
    }

    func resetCommands() { commands = AppSettings.defaultCommands }

    /// Mac src/config.js DEFAULTS.autoFixCommands ile birebir.
    static let defaultCommands: [FixCommand] = [
        .init(id: 1, name: "Relay servisini yeniden başlat",
              command: "for svc in anon anon@default anyone anyone-relay tor-anon; do systemctl cat \"$svc\" >/dev/null 2>&1 && systemctl restart \"$svc\" && echo \"restarted: $svc\" && break; done"),
        .init(id: 2, name: "Servis durumu",
              command: "for svc in anon anon@default anyone anyone-relay tor-anon; do s=$(systemctl is-active \"$svc\" 2>/dev/null); [ -n \"$s\" ] && echo \"$svc=$s\"; done"),
        .init(id: 3, name: "Son 50 log satırı",
              command: "journalctl -u anon -n 50 --no-pager 2>/dev/null || journalctl -u anyone-relay -n 50 --no-pager 2>/dev/null || echo \"(log not found)\""),
        .init(id: 5, name: "SSH servisini yeniden başlat",
              command: "systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; echo \"ssh=$(systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null)\""),
        .init(id: 12, name: "Disk kullanımı",
              command: "df -h / /var /tmp 2>/dev/null"),
        .init(id: 13, name: "RAM ve yük",
              command: "free -m 2>/dev/null || vm_stat; uptime"),
        .init(id: 16, name: "Reboot gerekli mi?",
              command: "[ -f /var/run/reboot-required ] && cat /var/run/reboot-required || echo \"no reboot needed\""),
    ]
}
