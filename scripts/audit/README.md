# scripts/audit

Simulator ve Xcode projesi olmadan kosan denetim takimi: saf mantik dosyalari
`swiftc` ile derlenip dusmanca girdiyle CALISTIRILIR.

```bash
swiftc -Onone -o /tmp/rp-audit RelayPulse/Models/AgentMetrics.swift scripts/audit/main.swift && /tmp/rp-audit
```

Tuzaklar:
- Top-level kod icin dosya adi **main.swift** olmak zorunda, baska ad "expressions
  are not allowed at the top level" verir.
- `certpin-selfcheck.swift` `assert` kullaniyor; `assert` **-O ile derlenince
  tamamen kaybolur**. Her iki kosumu da `-Onone` ile derle, yoksa yesil gorunur
  ama hicbir sey kontrol edilmemis olur.

2026-09-22'de bulundugu hata icin commit `19b1469`.
