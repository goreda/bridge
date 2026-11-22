/// Compares two injected backend adapters on the same fixture and emits
/// measured TSV. See SPEC.md for the exact output contract.
public protocol ParityRunner {
    func run(fixture: String, seekTo: Double, left: any ProbeBackend, right: any ProbeBackend) throws -> String
}
