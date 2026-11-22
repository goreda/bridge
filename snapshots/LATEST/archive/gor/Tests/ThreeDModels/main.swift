import Foundation

/// 195h A (Delivery A-5) driver: the verify gate is request-aware, through the REAL ThreeDModels functions against the real
/// models.lock.tsv. Pure Foundation, Linux swiftc. Arg 1 = path to models.lock.tsv.
let lock = try! String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), encoding: .utf8)
let dav2Rows = ThreeDModels.gatedRows(lock: lock, dav2: true), kitRows = ThreeDModels.gatedRows(lock: lock, dav2: false)
print("dav2 gate rows \(dav2Rows.map { $0.id })")
print("kit gate rows \(kitRows.map { $0.id })")
print("dav2 gate is exactly the 3 pinned dav2 files \(dav2Rows.map { $0.id } == ["dav2-small-coreml-f16-model", "dav2-small-coreml-f16-weights", "dav2-small-coreml-f16-manifest"])")
print("kit gate unchanged: only coreml-kit rows, never dav2 \(!kitRows.isEmpty && kitRows.allSatisfy { $0.id.contains("coreml-kit") })")
print("fetch filter follows the request \(ThreeDModels.onlyID(dav2: true) == "dav2-small-coreml-f16" && ThreeDModels.onlyID(dav2: false) == "coreml-kit")")
// A DAV2-only install (dav2 files match their pins, kit files absent/wrong) satisfies the DAV2 gate - and the same install
// would still be unmet under the kit gate, which is exactly why the wiring must pick the gate by request.
let dav2Only: (URL) -> String? = { u in dav2Rows.first { u.path.hasSuffix($0.file) }?.sha }
let noDir = URL(fileURLWithPath: "/nonexistent-models")
print("DAV2-only install satisfies the DAV2 gate \(ThreeDModels.missing(dav2Rows, modelsDir: noDir, sha: dav2Only).isEmpty)")
print("same install is unmet under the kit gate (gate choice matters) \(!ThreeDModels.missing(kitRows, modelsDir: noDir, sha: dav2Only).isEmpty)")
print("dav2 rows never require a kit install marker \(dav2Rows.allSatisfy { ThreeDModels.kitInstalled($0, modelsDir: noDir) })")
