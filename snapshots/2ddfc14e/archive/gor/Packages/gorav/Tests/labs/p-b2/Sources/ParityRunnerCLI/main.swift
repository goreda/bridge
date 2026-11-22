import Foundation
import ParityCore

// parity-runner --stubs <stub.json> --fixture <name> --seek <seconds>
// Prints the measured TSV (header + one row per backend) to stdout.

func usage() -> Never {
    FileHandle.standardError.write(Data("usage: parity-runner --stubs <stub.json> --fixture <name> --seek <seconds>\n".utf8))
    exit(2)
}

var stubsPath: String?
var fixture: String?
var seekArg: String?

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--stubs": stubsPath = args.popFirst()
    case "--fixture": fixture = args.popFirst()
    case "--seek": seekArg = args.popFirst()
    default:
        FileHandle.standardError.write(Data("unknown argument: \(arg)\n".utf8))
        usage()
    }
}

guard let stubsPath, let fixture, let seekArg, let seek = Double(seekArg), seek.isFinite else {
    usage()
}

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: stubsPath))
    let stubs = try StubProbeBackend.load(fromJSON: data)
    let runner = TSVParityRunner()
    let tsv = try runner.run(fixture: fixture, seekTo: seek, left: stubs[0], right: stubs[1])
    FileHandle.standardOutput.write(Data(tsv.utf8))
} catch {
    FileHandle.standardError.write(Data("parity-runner: \(error)\n".utf8))
    exit(1)
}
