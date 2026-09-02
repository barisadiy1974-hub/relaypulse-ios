import Foundation
import Crypto
import NIOSSH

enum OpenSSHKeyError: LocalizedError {
    case badPEM
    case unsupportedCipher(String)
    case unsupportedType(String)
    case corrupt(String)

    var errorDescription: String? {
        switch self {
        case .badPEM: return "Anahtar dosyası OpenSSH formatında değil"
        case .unsupportedCipher(let c): return "Şifreli anahtar desteklenmiyor (\(c)) — parolasız ed25519 anahtar kullan"
        case .unsupportedType(let t): return "Desteklenmeyen anahtar tipi: \(t) (sadece ed25519)"
        case .corrupt(let m): return "Anahtar okunamadı: \(m)"
        }
    }
}

/// OpenSSH ("-----BEGIN OPENSSH PRIVATE KEY-----") formatındaki **parolasız
/// ed25519** özel anahtarını çözer. NIOSSH bu formatı kendi başına okumuyor.
enum OpenSSHKey {
    static func ed25519(fromPEM pem: String) throws -> NIOSSHPrivateKey {
        NIOSSHPrivateKey(ed25519Key: try curve25519(fromPEM: pem))
    }

    static func curve25519(fromPEM pem: String) throws -> Curve25519.Signing.PrivateKey {
        let body = pem
            .replacingOccurrences(of: "-----BEGIN OPENSSH PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END OPENSSH PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty, let blob = Data(base64Encoded: body) else { throw OpenSSHKeyError.badPEM }

        var r = Reader(blob)
        let magic = try r.take(15)
        guard magic == Data("openssh-key-v1\0".utf8) else { throw OpenSSHKeyError.badPEM }

        let cipher = try r.string()
        let kdf = try r.string()
        _ = try r.string()                       // kdfoptions
        guard cipher == "none", kdf == "none" else {
            throw OpenSSHKeyError.unsupportedCipher(cipher)
        }

        let nkeys = try r.uint32()
        guard nkeys == 1 else { throw OpenSSHKeyError.corrupt("beklenmeyen anahtar sayısı: \(nkeys)") }
        _ = try r.bytes()                        // public key blob

        var priv = Reader(try r.bytes())
        let c1 = try priv.uint32(), c2 = try priv.uint32()
        guard c1 == c2 else { throw OpenSSHKeyError.corrupt("checkint uyuşmuyor (anahtar parolalı olabilir)") }

        let type = try priv.string()
        guard type == "ssh-ed25519" else { throw OpenSSHKeyError.unsupportedType(type) }
        _ = try priv.bytes()                     // public (32)
        let secret = try priv.bytes()            // seed(32) || public(32)
        guard secret.count == 64 else { throw OpenSSHKeyError.corrupt("ed25519 gizli anahtar 64 bayt değil") }

        return try Curve25519.Signing.PrivateKey(rawRepresentation: secret.prefix(32))
    }

    // MARK: - Big-endian okuyucu

    private struct Reader {
        private let d: Data
        private var i: Int
        init(_ data: Data) { d = data; i = data.startIndex }

        mutating func take(_ n: Int) throws -> Data {
            guard n >= 0, i + n <= d.endIndex else { throw OpenSSHKeyError.corrupt("beklenmedik dosya sonu") }
            defer { i += n }
            return d[i..<(i + n)]
        }
        mutating func uint32() throws -> UInt32 {
            let b = try take(4)
            return b.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        mutating func bytes() throws -> Data {
            let n = Int(try uint32())
            return try take(n)
        }
        mutating func string() throws -> String {
            String(decoding: try bytes(), as: UTF8.self)
        }
    }
}
