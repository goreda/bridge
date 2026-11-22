import Foundation

/// Loads the literal fixture files bundled as test resources.
enum FixtureLoading {
    static func string(_ name: String) throws -> String {
        let url = Bundle.module.bundleURL
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
