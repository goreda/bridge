import Foundation

// Darwin fixture: same shared cases, built with the Darwin toolchain.
// swiftc -o t Sources/GorChromeVerbModel.swift Tests/GorChromeVerbCases.swift Tests/darwin/main.swift && ./t
// It adds a check that the Darwin Foundation parses the production JSON number forms the same way.
let failures = runGorChromeVerbCases()
var darwinFailures = failures
let sample = (try? JSONSerialization.jsonObject(with: Data(#"{"command":["multiply","speed",1.1]}"#.utf8)) as? [String: Any])?["command"] as? [Any] ?? []
if gorCommandNumber(sample, 2) != 1.1 { darwinFailures.append("darwin number decode 1.1") }
let intSample = (try? JSONSerialization.jsonObject(with: Data(#"{"command":["set_property","volume-max",200]}"#.utf8)) as? [String: Any])?["command"] as? [Any] ?? []
if gorCommandNumber(intSample, 2) != 200 { darwinFailures.append("darwin number decode 200") }
if darwinFailures.isEmpty {
    print("PASS gor-chrome-verbs darwin fixture")
} else {
    for f in darwinFailures { print("FAIL \(f)") }
    exit(1)
}
