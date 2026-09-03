import Foundation
import Crypto

/// License and 14-day trial system — mirrors Mac src/license.js.
///
/// Key format: RP1-<8 hex serial>-<86 char base64url signature>
/// The signature covers "RP1:<serial>" with the Ed25519 private key.
/// Public key (base64): /xXI756LTRLUTK5d98c7s9UPeZD9yjUflw9u2cMUkOw=
enum LicenseStore {

    private static let publicKeyB64 = "/xXI756LTRLUTK5d98c7s9UPeZD9yjUflw9u2cMUkOw="
    private static let trialDays = 14
    private static let firstLaunchKey = "firstLaunchAt"
    private static let licenseKey = "licenseKey"

    // MARK: - State

    enum State {
        case licensed(serial: String)
        case trial(daysLeft: Int)
        case expired
    }

    static var state: State {
        // Licensed?
        let key = storedKey
        if !key.isEmpty, verify(key) { return .licensed(serial: serial(from: key) ?? "") }

        // Trial
        let first = firstLaunch
        let elapsed = Int(Date().timeIntervalSince(first) / 86400)
        let left = trialDays - elapsed
        return left > 0 ? .trial(daysLeft: left) : .expired
    }

    static var isActive: Bool {
        switch state {
        case .licensed, .trial: return true
        case .expired: return false
        }
    }

    // MARK: - License key entry

    static var storedKey: String {
        get { UserDefaults.standard.string(forKey: licenseKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: licenseKey) }
    }

    /// Validates and stores a key. Returns true on success.
    @discardableResult
    static func activate(_ raw: String) -> Bool {
        let k = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard verify(k) else { return false }
        storedKey = k
        return true
    }

    static func deactivate() { storedKey = "" }

    // MARK: - Trial

    static var firstLaunch: Date {
        if let t = UserDefaults.standard.object(forKey: firstLaunchKey) as? Double {
            return Date(timeIntervalSince1970: t)
        }
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: firstLaunchKey)
        return now
    }

    // MARK: - Verification

    static func verify(_ key: String) -> Bool {
        // Format: RP1-<8 hex>-<base64url sig>
        let parts = key.split(separator: "-", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "RP1", parts[1].count == 8 else { return false }

        let message = Data("RP1:\(parts[1])".utf8)
        // Convert base64url → base64
        var b64 = parts[2].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }

        guard let sigData = Data(base64Encoded: b64),
              let pubKeyData = Data(base64Encoded: publicKeyB64),
              let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData) else { return false }

        return pubKey.isValidSignature(sigData, for: message)
    }

    private static func serial(from key: String) -> String? {
        let parts = key.split(separator: "-", maxSplits: 2)
        return parts.count == 3 ? String(parts[1]) : nil
    }
}
