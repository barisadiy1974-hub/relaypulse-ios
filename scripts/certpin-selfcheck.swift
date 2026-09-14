// Self-check for CertPin's trust-on-first-use rule. Run it after touching
// CertPin — it is the one piece here that decides whether an agent token is
// handed to a stranger.
//
//   swiftc RelayPulse/Net/CertPin.swift scripts/certpin-selfcheck.swift -o /tmp/cpc && /tmp/cpc
import Foundation

@main
enum CertPinSelfCheck {
    static func main() {
    CertPin.reset()
    assert(CertPin.accepts(host: "relay-a", hash: "K1"), "first sight must be learned")
    assert(CertPin.accepts(host: "relay-a", hash: "K1"), "same key must keep passing")
    assert(!CertPin.accepts(host: "relay-a", hash: "K2"), "a different key is the attack we block")
    assert(CertPin.accepts(host: "relay-b", hash: "K2"), "pins are per host")
    assert(CertPin.count == 2)

    CertPin.markRejected("relay-a")
    assert(CertPin.takeRejection("relay-a"), "rejection must reach the error message")
    assert(!CertPin.takeRejection("relay-a"), "and only once")

    CertPin.reset()
    assert(CertPin.count == 0)
    assert(CertPin.accepts(host: "relay-a", hash: "K2"), "reset relearns after a reinstall")
    CertPin.reset()
    print("certpin-selfcheck: ok")
    }
}
