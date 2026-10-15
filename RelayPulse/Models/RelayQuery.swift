import Foundation

/// The fleet search box. Plain text matches name or IP as before; a number
/// range like "10-25" (also "10 - 25", "10..25") keeps relays whose number is
/// in it, and parts can be mixed: "10-25, 40-45, exit". Same rules as desktop
/// (renderer/app.js parseRelayQuery) and Android (RelayQuery.kt).
struct RelayQuery {
    private enum Term {
        case text(String)
        case range(Int, Int)
    }

    private let raw: String
    /// Nil when the query has no range: then the whole text is searched, commas included.
    private let terms: [Term]?

    init(_ query: String) {
        raw = query.trimmingCharacters(in: .whitespaces)
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let parsed: [Term] = parts.map { p in
            if let (a, b) = RelayQuery.range(p) { return .range(min(a, b), max(a, b)) }
            return .text(p)
        }
        let hasRange = parsed.contains { if case .range = $0 { return true }; return false }
        terms = hasRange ? parsed : nil
    }

    func matches(name: String, host: String = "") -> Bool {
        if raw.isEmpty { return true }
        guard let terms else {
            return name.localizedCaseInsensitiveContains(raw) || host.localizedCaseInsensitiveContains(raw)
        }
        let num = RelayQuery.number(name)
        return terms.contains { t in
            switch t {
            case .text(let s):
                return name.localizedCaseInsensitiveContains(s) || host.localizedCaseInsensitiveContains(s)
            case .range(let lo, let hi):
                guard let n = num else { return false }
                return n >= lo && n <= hi
            }
        }
    }

    /// The relay's number is the last run of digits in its name: Barisfreak119b -> 119.
    static func number(_ name: String) -> Int? {
        var digits = ""
        var seenDigit = false
        for ch in name.reversed() {
            if ch.isASCII && ch.isNumber {
                digits.insert(ch, at: digits.startIndex)
                seenDigit = true
            } else if seenDigit {
                break
            }
        }
        return digits.isEmpty ? nil : Int(digits.prefix(9))
    }

    /// "10-25", "10 - 25", "10..25", "10–25", "10 to 25" -> (10, 25).
    private static func range(_ part: String) -> (Int, Int)? {
        let p = part.lowercased()
        for sep in ["..", "–", "-", " to "] {
            let sides = p.components(separatedBy: sep)
            guard sides.count == 2 else { continue }
            let a = sides[0].trimmingCharacters(in: .whitespaces)
            let b = sides[1].trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty, !b.isEmpty, a.allSatisfy({ $0.isASCII && $0.isNumber }),
                  b.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let x = Int(a.prefix(9)), let y = Int(b.prefix(9)) else { continue }
            return (x, y)
        }
        return nil
    }
}
