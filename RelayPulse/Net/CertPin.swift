import CryptoKit
import Foundation

/// Trust-on-first-use pinning for the relay agents' self-signed certificates.
///
/// The agent proves nothing by its certificate — it is self-signed — so before
/// this the app accepted any certificate and handed `X-Agent-Token` to whoever
/// answered on port 9999. Anyone able to sit between the phone and the relay
/// (hotel wifi, a hostile upstream) could collect the token of every relay in
/// the fleet by presenting their own certificate.
///
/// The public key is remembered the first time a relay answers and every later
/// connection must present the same one. A mismatch is refused, the sweep falls
/// back to SSH, and the card says the certificate changed.
///
/// ponytail: TOFU, so a first connection made through an attacker is pinned to
/// the attacker. Pinning the agent's key at install time would close that, and
/// needs the installer to carry the key back.
enum CertPin {
    private static let key = "agentCertPins"
    private static let lock = NSLock()
    private static var rejected: Set<String> = []

    /// SHA-256 of the leaf certificate's public key — the key, not the
    /// certificate, so renewing an expiring certificate does not trip the pin.
    static func publicKeyHash(_ trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let pub = SecCertificateCopyKey(leaf),
              let der = SecKeyCopyExternalRepresentation(pub, nil) as Data? else { return nil }
        return Data(SHA256.hash(data: der)).base64EncodedString()
    }

    /// Accepts and stores on first sight; afterwards only the stored key passes.
    static func accepts(host: String, hash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var pins = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        guard let known = pins[host] else {
            pins[host] = hash
            UserDefaults.standard.set(pins, forKey: key)
            return true
        }
        return known == hash
    }

    static func markRejected(_ host: String) {
        lock.lock(); rejected.insert(host); lock.unlock()
    }

    /// Reads and clears — a rejection explains exactly one failed request.
    static func takeRejection(_ host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rejected.remove(host) != nil
    }

    /// For the operator who really did reinstall an agent. Forgets every pin;
    /// the next sweep learns the current keys.
    static func reset() {
        lock.lock()
        UserDefaults.standard.removeObject(forKey: key)
        rejected.removeAll()
        lock.unlock()
    }

    static var count: Int {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?.count ?? 0
    }
}
