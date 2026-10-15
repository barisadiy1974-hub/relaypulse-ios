// Logic checks for 1.0.14: range search, instance keys and box readings split
// per relay. Built with swiftc -Onone next to the model files (see audit.yml);
// `check` instead of assert so a failure prints what went wrong.
import Foundation

@main
enum FleetSelfCheck {
    static var failures = 0
    static func check(_ ok: Bool, _ what: String) {
        if ok { print("ok   \(what)") } else { print("FAIL \(what)"); failures += 1 }
    }

    static func main() {
        // Range search
        let names = ["Barisfreak9", "Barisfreak10", "Barisfreak19b", "Barisfreak25", "Barisfreak26", "Barisfreak119b", "barisa1", "exit-node"]
        func shown(_ q: String) -> [String] { let r = RelayQuery(q); return names.filter { r.matches(name: $0) } }
        check(RelayQuery.number("Barisfreak119b") == 119, "number of Barisfreak119b is 119")
        check(RelayQuery.number("exit-node") == nil, "exit-node has no number")
        check(shown("010 - 025") == ["Barisfreak10", "Barisfreak19b", "Barisfreak25"], "range 010 - 025")
        check(shown("10-25") == shown("25..10"), "range order does not matter")
        check(shown("1-9, 100-200, exit") == ["Barisfreak9", "Barisfreak119b", "barisa1", "exit-node"], "several parts and text")
        check(shown("119") == ["Barisfreak119b"], "plain text search unchanged")
        check(RelayQuery("1.2.3").matches(name: "x", host: "1.2.3.4"), "IP search unchanged")
        check(shown("  ") == names, "empty search shows all")

        // Instance keys (same as Android Server.agentInstanceKey)
        check(Server(name: "a", host: "h").agentInstanceKey == "", "first relay key is empty")
        check(Server(name: "a", host: "h", instance: "3").agentInstanceKey == "3", "instance 3")
        check(Server(name: "a", host: "h", instance: "anon12").agentInstanceKey == "12", "instance anon12")
        check(Server(name: "a", host: "h", instance: "relayB").instanceUnit == "anon@relayB", "named instance unit")
        check(Server(name: "a", host: "h", agentPort: 19191).usesAgent, "box row uses its agent")
        check(!Server(name: "a", host: "h", agentPort: 0, instance: "3").usesAgent, "instance row does not")

        // Export decoding keeps the new fields
        let json = #"{"name":"Barisfreak50c","host":"2.26.172.203","agentPort":0,"instance":"3","fingerprint":"ff57757eb1cfa6e871adfffc05dd88ee021754db","note":"Freak"}"#
        let s = try! JSONDecoder().decode(Server.self, from: Data(json.utf8))
        check(s.instance == "3" && s.note == "Freak" && s.fingerprint.hasPrefix("FF57"), "export fields decoded")
        let back = try! JSONDecoder().decode(Server.self, from: try! JSONEncoder().encode(s))
        check(back.instance == "3" && back.note == "Freak", "fields survive save and load")

        // Box reading narrowed per relay
        let box = #"{"conn":40,"anon":{"active":"active","ports":["9001"],"services":{"anon@default":"active"}},"agentVersion":2,"instances":{"":{"services":{"anon@default":"active"},"ports":["0.0.0.0:9001"],"conn":12},"3":{"services":{"anon3":"inactive"},"ports":[],"conn":0},"4":{"services":{},"ports":["1.2.3.4:9401"],"conn":5}}}"#
        let m = try! JSONDecoder().decode(AgentMetrics.self, from: Data(box.utf8))
        check(m.instances?.count == 3, "three relays on the box")
        check(m.forInstance("3")?.anon?.active == "inactive", "stopped instance reads inactive")
        check(m.forInstance("3")?.anonHealthy(expectService: true) == false, "stopped instance is not healthy")
        check(m.forInstance("4")?.anon?.active == "active", "port only, no unit state: active")
        check(m.forInstance("")?.conn == 12, "first relay's own connections")
        check(m.forInstance("9") == nil, "unknown relay: nil (then SSH)")
        check(m.ownOf("").conn == 12, "box row shows its own relay")

        if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
        print("all checks passed")
    }
}
