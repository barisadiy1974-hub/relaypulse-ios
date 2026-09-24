import Foundation
import Crypto

/// The phone's dedicated SSH private key — stored in Keychain under "sshPrivateKey".
/// This is NOT one of the fleet's 3 Mac keys; it is a separate, revocable phone key.
enum SSHKeyStore {
    static var pem: String { Keychain.get("sshPrivateKey") }
    static var hasKey: Bool { !pem.isEmpty }

    /// Validates the PEM and stores it. Throws on invalid input without writing anything.
    static func store(_ pem: String) throws {
        _ = try OpenSSHKey.ed25519(fromPEM: pem)   // validate
        Keychain.set(pem.trimmingCharacters(in: .whitespacesAndNewlines), for: "sshPrivateKey")
    }

    static func clear() { Keychain.delete("sshPrivateKey") }

    /// A server's own login password, for servers the phone has no key on —
    /// the same choice desktop RelayPulse offers per server. Keychain, keyed by
    /// server name; FleetStore moves or deletes it with the server.
    static func password(for server: String) -> String { Keychain.get("sshPassword:" + server) }
    static func setPassword(_ pw: String, for server: String) {
        pw.isEmpty ? Keychain.delete("sshPassword:" + server) : Keychain.set(pw, for: "sshPassword:" + server)
    }
    static func canLogin(_ server: Server) -> Bool { hasKey || !password(for: server.name).isEmpty }

    /// Same comment the website's ssh-keygen line uses, so one `sed` removes
    /// the phone key from a relay however it was made.
    static let comment = "relaypulse-phone"

    /// Makes the key on the phone itself, so the private half never has to
    /// travel from a computer. Never replaces a loaded key.
    static func generate() throws {
        guard !hasKey else { return }
        try store(OpenSSHKey.pem(Curve25519.Signing.PrivateKey(), comment: comment))
    }

    /// The line that goes into a relay's authorized_keys.
    static var publicKeyLine: String? {
        guard let key = try? OpenSSHKey.curve25519(fromPEM: pem) else { return nil }
        return OpenSSHKey.publicLine(key.publicKey, comment: comment)
    }

    /// Appends the public key unless it is already there. The line is base64
    /// plus a fixed comment, so it is safe inside single quotes.
    static var installCommand: String? {
        guard let line = publicKeyLine else { return nil }
        return """
        umask 077; mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && \
        { grep -qxF '\(line)' ~/.ssh/authorized_keys || echo '\(line)' >> ~/.ssh/authorized_keys; } && \
        chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && echo KEY_INSTALLED
        """
    }

    /// SHA256 fingerprint of the key (same format as `ssh-keygen -lf`).
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

    /// At first launch, reads `Documents/ssh_key.pem`, stores it in Keychain, and deletes the file.
    /// Used to seed the key from Mac via `devicectl device copy to`.
    static func importSeedFileIfPresent() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = dir.appendingPathComponent("ssh_key.pem")
        guard let data = try? Data(contentsOf: f),
              let text = String(data: data, encoding: .utf8) else { return }
        do {
            try store(text)
            // Only delete on success — a corrupt seed file would otherwise disappear silently.
            try? FileManager.default.removeItem(at: f)
        } catch {
            NSLog("SSHKeyStore: could not read seed key — \(error.localizedDescription)")
        }
    }
}
