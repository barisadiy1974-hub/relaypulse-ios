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
        case .badPEM: return "The key file is not in OpenSSH format"
        case .unsupportedCipher(let c): return "Encrypted keys are not supported (\(c)) — use an unencrypted ed25519 key"
        case .unsupportedType(let t): return "Unsupported key type: \(t) (ed25519 only)"
        case .corrupt(let m): return "Could not read the key: \(m)"
        }
    }
}

/// Parses an **unencrypted ed25519** private key in OpenSSH format
/// ("-----BEGIN OPENSSH PRIVATE KEY-----"). NIOSSH does not read this format itself.
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
        guard nkeys == 1 else { throw OpenSSHKeyError.corrupt("unexpected key count: \(nkeys)") }
        _ = try r.bytes()                        // public key blob

        var priv = Reader(try r.bytes())
        let c1 = try priv.uint32(), c2 = try priv.uint32()
        guard c1 == c2 else { throw OpenSSHKeyError.corrupt("checkint mismatch (the key may be passphrase-protected)") }

        let type = try priv.string()
        guard type == "ssh-ed25519" else { throw OpenSSHKeyError.unsupportedType(type) }
        _ = try priv.bytes()                     // public (32)
        let secret = try priv.bytes()            // seed(32) || public(32)
        guard secret.count == 64 else { throw OpenSSHKeyError.corrupt("ed25519 secret is not 64 bytes") }

        return try Curve25519.Signing.PrivateKey(rawRepresentation: secret.prefix(32))
    }

    // MARK: - Writing

    /// The `authorized_keys` line for a key: "ssh-ed25519 <base64> <comment>".
    static func publicLine(_ key: Curve25519.Signing.PublicKey, comment: String) -> String {
        "ssh-ed25519 \(publicBlob(key).base64EncodedString()) \(comment)"
    }

    /// Unencrypted "openssh-key-v1" PEM — the same thing
    /// `ssh-keygen -t ed25519 -N ""` writes, so the reader above takes it back.
    static func pem(_ key: Curve25519.Signing.PrivateKey, comment: String) -> String {
        let pub = key.publicKey.rawRepresentation
        var priv = Data()
        let check = UInt32.random(in: .min ... .max)
        priv.u32(check); priv.u32(check)
        priv.str(Data("ssh-ed25519".utf8))
        priv.str(pub)
        priv.str(key.rawRepresentation + pub)          // seed(32) || public(32)
        priv.str(Data(comment.utf8))
        var pad: UInt8 = 1
        while priv.count % 8 != 0 { priv.append(pad); pad += 1 }

        var blob = Data("openssh-key-v1\0".utf8)
        blob.str(Data("none".utf8))                    // cipher
        blob.str(Data("none".utf8))                    // kdf
        blob.str(Data())                               // kdf options
        blob.u32(1)                                    // key count
        blob.str(publicBlob(key.publicKey))
        blob.str(priv)

        let b64 = blob.base64EncodedString()
        let lines = stride(from: 0, to: b64.count, by: 70).map { i -> String in
            let s = b64.index(b64.startIndex, offsetBy: i)
            let e = b64.index(s, offsetBy: 70, limitedBy: b64.endIndex) ?? b64.endIndex
            return String(b64[s..<e])
        }
        return (["-----BEGIN OPENSSH PRIVATE KEY-----"] + lines + ["-----END OPENSSH PRIVATE KEY-----"])
            .joined(separator: "\n") + "\n"
    }

    private static func publicBlob(_ key: Curve25519.Signing.PublicKey) -> Data {
        var d = Data()
        d.str(Data("ssh-ed25519".utf8))
        d.str(key.rawRepresentation)
        return d
    }

    // MARK: - Big-endian reader

    private struct Reader {
        private let d: Data
        private var i: Int
        init(_ data: Data) { d = data; i = data.startIndex }

        mutating func take(_ n: Int) throws -> Data {
            guard n >= 0, i + n <= d.endIndex else { throw OpenSSHKeyError.corrupt("unexpected end of file") }
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

private extension Data {
    mutating func u32(_ v: UInt32) { Swift.withUnsafeBytes(of: v.bigEndian) { append(contentsOf: $0) } }
    mutating func str(_ d: Data) { u32(UInt32(d.count)); append(d) }
}
