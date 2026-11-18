import Foundation

// Linux-runnable: swiftc -o t Sources/GorChromeVerbModel.swift Tests/GorChromeVerbCases.swift Tests/linux/main.swift && ./t
let failures = runGorChromeVerbCases()
if failures.isEmpty {
    print("PASS gor-chrome-verbs linux model cases")
} else {
    for f in failures { print("FAIL \(f)") }
    exit(1)
}
