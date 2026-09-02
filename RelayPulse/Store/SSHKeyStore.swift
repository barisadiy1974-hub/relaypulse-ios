import Foundation
import Crypto

/// Telefonun SSH özel anahtarı — Keychain'de (`sshPrivateKey`).
/// Filoya ait 3 Mac anahtarı DEĞİL; telefona özel, tek başına iptal edilebilir anahtar.
enum SSHKeyStore {
    static var pem: String { Keychain.get("sshPrivateKey") }
    static var hasKey: Bool { !pem.isEmpty }

    /// PEM'i doğrular ve saklar. Geçersizse hata fırlatır, hiçbir şey yazmaz.
    static func store(_ pem: String) throws {
        _ = try OpenSSHKey.ed25519(fromPEM: pem)   // doğrulama
        Keychain.set(pem.trimmingCharacters(in: .whitespacesAndNewlines), for: "sshPrivateKey")
    }

    static func clear() { Keychain.delete("sshPrivateKey") }

    /// Anahtarın SHA256 parmak izi (ssh-keygen -lf ile aynı biçim).
    static var fingerprint: String? {
        guard let key = try? OpenSSHKey.curve25519(fromPEM: pem) else { return nil }
        var blob = Data()
        func str(_ d: Data) {
            var n = UInt32(d.count).bigEndian
            withUnsafeBytes(of: &n) { blob.append(contentsOf: $0) }
            blob.append(d)
        }
        str(Data("ssh-ed25519".utf8))
        str(Data(key.publicKey.rawRepresentation))
        let digest = SHA256.hash(data: blob)
        let b64 = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(b64)"
    }

    /// İlk kurulumda `Documents/ssh_key.pem` varsa Keychain'e alır ve dosyayı siler.
    /// (Mac'ten `devicectl device copy to` ile tohumlamak için.)
    static func importSeedFileIfPresent() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = dir.appendingPathComponent("ssh_key.pem")
        guard let data = try? Data(contentsOf: f),
              let text = String(data: data, encoding: .utf8) else { return }
        do {
            try store(text)
            // Sadece basarili olursa sil — yoksa bozuk bir tohum sessizce kaybolurdu.
            try? FileManager.default.removeItem(at: f)
        } catch {
            NSLog("SSHKeyStore: tohum anahtar okunamadi — \(error.localizedDescription)")
        }
    }
}
