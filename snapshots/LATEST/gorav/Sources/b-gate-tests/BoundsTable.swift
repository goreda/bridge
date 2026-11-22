import Foundation

/// Cited bounds loaded from kits/bounds-table/bounds.json (read-only).
/// Usage at the two call sites in main.swift (integrator applies; full file not in packet):
///   B1 resume waitFor timeout:        BoundsTable.shared.seconds("resume-after-pause landing")
///   B2 audio-landing waitFor timeout: BoundsTable.shared.seconds("post-seek audio landing")
struct BoundsTable {
    struct Row: Decodable {
        let name: String
        let value: Double
        let unit: String
        let kind: String
        let citation: String
        let confidence: String
    }
    struct File: Decodable { let rows: [Row] }

    let rows: [String: Row]

    static let shared: BoundsTable = {
        // BGATE_BOUNDS_JSON overrides; default is repo-relative to the working directory.
        let path = ProcessInfo.processInfo.environment["BGATE_BOUNDS_JSON"]
            ?? "kits/bounds-table/bounds.json"
        guard let data = FileManager.default.contents(atPath: path),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            FileHandle.standardError.write(Data("b-gate: cannot load bounds table at \(path)\n".utf8))
            exit(2)
        }
        return BoundsTable(rows: Dictionary(uniqueKeysWithValues: file.rows.map { ($0.name, $0) }))
    }()

    /// Seconds for a named row; exits 2 if the row is missing or uncited (no inline fallback).
    func seconds(_ name: String) -> Double {
        guard let r = rows[name], !r.citation.isEmpty, r.value > 0 else {
            FileHandle.standardError.write(Data("b-gate: bound '\(name)' missing or uncited\n".utf8))
            exit(2)
        }
        return r.unit == "ms" ? r.value / 1000 : r.value
    }
}
