import Foundation
import GorAVPlaybackCore

// photon-sharp-tests (P23 photon-sharp ingest, DR-0022, lane c): byte-lock
// witness for PhotonSharpShaderGenerator. Emits both routes and compares
// BYTE-FOR-BYTE against the committed fixtures, which are the live-Lua
// captures from the pinned photon-sharp.lua (sha256 f9aeedb4...46d1;
// generator surface byte-identical on current instinct main 555a3318...).
// Fixture hashes (sha256):
//   fixtures/photon-sharp.glsl          bd88d888d9fb8cfd84c909e27438e00a8796ab965362c94975382eeda0f90761
//   fixtures/photon-sharp-temporal.glsl  e12441759cce0e7e271f663ac3aa2999a25ef6bc307016c01fade9a3643083bc

var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool) {
    if cond { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}

func fixture(_ name: String) -> String {
    let url = URL(fileURLWithPath: "Sources/photon-sharp-tests/fixtures/\(name)")
    guard let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else {
        print("FAIL fixture-unreadable \(name)"); exit(1)
    }
    return s
}

let mainFixture = fixture("photon-sharp.glsl")
let temporalFixture = fixture("photon-sharp-temporal.glsl")

let mainEmitted = PhotonSharpShaderGenerator.emitGLSL(route: .main)
let temporalEmitted = PhotonSharpShaderGenerator.emitGLSL(route: .temporal)

check("main.byteEqual", mainEmitted == mainFixture)
check("temporal.byteEqual", temporalEmitted == temporalFixture)
check("main.length", mainEmitted.utf8.count == 19638)
check("temporal.length", temporalEmitted.utf8.count == 21755)
check("main.bakedDefine", mainEmitted.contains("#define PHOTON_SHARP_AMOUNT_CEIL      128.00"))
check("main.noCompute", !mainEmitted.contains("//!COMPUTE"))
check("temporal.hasCompute", temporalEmitted.contains("//!COMPUTE"))
check("temporal.isMainPlusPhase2", temporalEmitted.hasPrefix(mainEmitted))
check("routes.allCovered", PhotonSharpShaderGenerator.SharpRoute.allCases.count == 2)
check("params.count19", PhotonSharpShaderGenerator.glslParamNames.count == 19)
check("params.p22laneOrder", PhotonSharpShaderGenerator.glslParamNames
        == ["PHOTON_SHARP_FRAME_PEAK", "PHOTON_SHARP_SCENE_CONTRAST",
            "PHOTON_SHARP_NOISE_LEVEL", "PHOTON_SHARP_MOTION_LEVEL",
            "PHOTON_SHARP_AMOUNT", "PHOTON_SHARP_FINE_COARSE",
            "PHOTON_SHARP_FACTOR_RENDERED", "PHOTON_SHARP_TEMPORAL_ALPHA",
            "PHOTON_SHARP_HALO_GUARD", "PHOTON_SHARP_TEXTURE_BIAS",
            "PHOTON_SHARP_FINE_STRENGTH", "PHOTON_SHARP_MEDIUM_STRENGTH",
            "PHOTON_SHARP_COARSE_STRENGTH", "PHOTON_SHARP_ALGO",
            "PHOTON_SHARP_BLOCK_LEVEL", "PHOTON_SHARP_RING_LEVEL",
            "PHOTON_SHARP_CONTENT_ADAPT", "PHOTON_SHARP_MEDIUM_BAND_ACTIVE",
            "PHOTON_SHARP_COARSE_BAND_ACTIVE"])
// Default-only API: the emitted text carries exactly one AMOUNT_CEIL define,
// at the locked 128.0 value.
check("define.once", mainEmitted.components(separatedBy: "#define PHOTON_SHARP_AMOUNT_CEIL").count - 1 == 1)

// -- bake() rewrite contract: precision mutants and negative cases --------
// (added for goreda's P23 packet 02 reuse; the locked value is always 128.0,
// formatted exactly like the Lua string.format("%.2f")).
let lockedLine = "#define PHOTON_SHARP_AMOUNT_CEIL      128.00"
check("bake.minimalSpacing", PhotonSharpShaderGenerator.bake("#define PHOTON_SHARP_AMOUNT_CEIL 999") == lockedLine)
check("bake.negativeValue", PhotonSharpShaderGenerator.bake("#define PHOTON_SHARP_AMOUNT_CEIL      -3.5") == lockedLine)
check("bake.tabSpacing", PhotonSharpShaderGenerator.bake("#define PHOTON_SHARP_AMOUNT_CEIL\t 12.75") == lockedLine)
check("bake.allOccurrences", PhotonSharpShaderGenerator.bake(
        "#define PHOTON_SHARP_AMOUNT_CEIL 1\n#define PHOTON_SHARP_AMOUNT_CEIL 2")
        == lockedLine + "\n" + lockedLine)
check("bake.noDefineUntouched", PhotonSharpShaderGenerator.bake("no define here") == "no define here")
// Negative boundary: a nan/inf define does NOT match the Lua regex
// (-?[0-9.]+), so bake leaves it in place - the mirror is faithful, which is
// exactly why the public arbitrary-value parameter was dropped (DR-0022).
check("bake.nanNotRewritten", PhotonSharpShaderGenerator.bake("#define PHOTON_SHARP_AMOUNT_CEIL      nan")
        == "#define PHOTON_SHARP_AMOUNT_CEIL      nan")
check("bake.infNotRewritten", PhotonSharpShaderGenerator.bake("#define PHOTON_SHARP_AMOUNT_CEIL      inf")
        == "#define PHOTON_SHARP_AMOUNT_CEIL      inf")

print("FINAL pass=\(pass) fail=\(fail)")
exit(fail == 0 ? 0 : 1)
