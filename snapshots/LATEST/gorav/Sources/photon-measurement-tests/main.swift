import Foundation
import GorAVPlaybackCore
import GorAVMetalPresenter

// photon-measurement-tests (DR-0017, queue item 198a-5b/photon V3 binding, lane c):
// Linux witness for the photon V3 measurement binding. Covers the CPU-witnessable
// contract: the lane b measurement/model handoff files installed verbatim, the P22
// layout extension (offsets, mask, supported-bin interpolation, typed refusal), the
// canonical stage insertion, and the shader-source fence declarations. Metal
// compile/execution: NOT_RUN (no GPU on this host).

var pass = 0, fail = 0
func check(_ name: String, _ cond: Bool) {
    if cond { pass += 1 } else { fail += 1; print("FAIL \(name)") }
}

let binding = PhotonSourceBinding(session: 7, generation: 3, frameIndex: 42)
let other = PhotonSourceBinding(session: 7, generation: 3, frameIndex: 43)

// -- A. Installed handoff types: binding/admission contract -------------------
let rect = PhotonPictureRect(x: 0, y: 0, width: 64, height: 64)
check("A1.rectValid", rect.valid(width: 64, height: 64))
check("A2.rectTooSmallRefused", !PhotonPictureRect(x: 0, y: 0, width: 6, height: 64).valid(width: 64, height: 64))
check("A3.rectOverflowRefused", !PhotonPictureRect(x: 10, y: 0, width: 64, height: 64).valid(width: 64, height: 64))

func measurement(sigma: [Double], counts: [Int], domain: PhotonMeasurementDomain = .decodedSDRSignal) -> PhotonSourceMeasurement {
    PhotonSourceMeasurement(binding: binding, domain: domain, pictureRect: rect,
                            sigma: sigma, counts: counts, sourceCellPixels: nil, cellConfidence: 0)
}
let good = measurement(sigma: [0.02, 0.021, 0.022, 0.023, 0.024, 0.025, 0.026, 0.027],
                       counts: [100, 100, 100, 100, 100, 100, 100, 100])
check("A4.admitsExact", good.admits(binding, domain: .decodedSDRSignal))
check("A5.frameMismatchRefused", !good.admits(other, domain: .decodedSDRSignal))
check("A6.domainMismatchRefused", !good.admits(binding, domain: .decodedPQSignal))
check("A7.wrongBinCountRefused", !measurement(sigma: [0.02], counts: [100]).admits(binding, domain: .decodedSDRSignal))
check("A8.nonFiniteSigmaRefused", !measurement(sigma: [.nan, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02],
                                              counts: [100, 100, 100, 100, 100, 100, 100, 100]).admits(binding, domain: .decodedSDRSignal))

// -- B. CPU reference measure on synthetic decoded luma ------------------------
// Flat field at the bin-4 center 0.5625 with planted uniform residual +/-0.01
// (checkerboard): the 5x5 denoise drift (+/-0.0004) stays inside bin 4, so all
// samples land there; sigma of a +/-0.01 two-point residual ~= 0.01.
do {
    let w = 64, h = 64
    var luma = [Float](repeating: 0.5625, count: w * h)
    for y in 0..<h { for x in 0..<w { luma[y * w + x] += ((x + y) % 2 == 0) ? 0.01 : -0.01 } }
    let m = try PhotonSourceMeasurementReference.measure(luma: luma, width: w, height: h, rect: rect,
                                                         binding: binding, domain: .decodedSDRSignal)
    check("B1.referenceBin4Only", m.counts[4] > 0 && m.counts.enumerated().allSatisfy { $0.0 == 4 || $0.1 == 0 })
    check("B2.referenceSigma", abs(m.sigma[4] - 0.01) < 0.002)
    check("B3.noSourceCellSynthesis", m.sourceCellPixels == nil && m.cellConfidence == 0)
    check("B4.bindingCarried", m.binding == binding && m.domain == .decodedSDRSignal)
} catch { check("B0.referenceThrew", false) }
// Edges excluded: a sharp 0/1 horizontal step keeps the two flat plateaus
// (bins 0 and 7, 26 interior rows x 58 columns each) and excludes the
// transition rows via the gradient threshold.
do {
    let w = 64, h = 64
    let luma = [Float](repeating: 0, count: w * h / 2) + [Float](repeating: 1, count: w * h / 2)
    let m = try PhotonSourceMeasurementReference.measure(luma: luma, width: w, height: h, rect: rect,
                                                         binding: binding, domain: .decodedSDRSignal)
    check("B5.edgeRowsExcluded", m.counts[0] == 26 * 58 && m.counts[7] == 26 * 58
          && m.counts.enumerated().allSatisfy { [0, 7].contains($0.0) || $0.1 == 0 })
} catch { check("B5.edgeFieldThrew", false) }

// -- C. P22 layout extension ----------------------------------------------------
check("C1.wireAgreement", PhotonMeasurementP22.statsWireBytes == 64 && PhotonMeasurementP22.sigmaByteOffset == 0
      && PhotonMeasurementP22.countsByteOffset == 32 && PhotonMeasurementP22.extensionBytes == 72)
check("C2.binCenters", abs(PhotonMeasurementP22.binCenter(0) - 0.0625) < 1e-12 && abs(PhotonMeasurementP22.binCenter(7) - 0.9375) < 1e-12)
let maskSigma = [0.0, 0.021, 0.0, 0.023, 0.0, 0.0, 0.0, 0.0]
let maskCounts = [10, 100, 0, 64, 33, 31, 0, 5]  // count>=32 at bins 1,3,4,5; bin 5 just under at 31
let m = PhotonMeasurementP22.mask(sigma: maskSigma, counts: maskCounts)
check("C3.maskBits", m == 0b11010)  // bins 1, 3, 4
check("C4.maskEmpty", PhotonMeasurementP22.mask(sigma: [Double](repeating: 0, count: 8), counts: [Int](repeating: 0, count: 8)) == 0)
// packed bytes: 72 long, sigma word of bin 1 at offset 4, counts of bin 1 at 36, mask at 64, reserved 0 at 68
let packed = PhotonMeasurementP22.packExtensionBytes(sigma: maskSigma, counts: maskCounts)
func word(_ b: [UInt8], _ o: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[o + $1]) << (8 * $1) } }
check("C5.packLength", packed.count == 72)
check("C6.packSigmaBin1", word(packed, 4) == Float(0.021).bitPattern)
check("C7.packSigmaBin0Zeroed", word(packed, 0) == Float(0).bitPattern)
check("C8.packCountsKept", word(packed, 32) == 10 && word(packed, 36) == 100)
check("C9.packMaskReserved", word(packed, 64) == m && word(packed, 68) == 0)

// interpolation over supported bins only: bins 1 (center 0.1875, sigma 0.021), 3 (center 0.4375, sigma 0.023) and 4 (center 0.5625, sigma 0, genuinely measured flat)
let sSigma = [0.0, 0.021, 0.0, 0.023, 0.0, 0.0, 0.0, 0.0]
let sCounts = [0, 100, 0, 100, 100, 0, 0, 0]
do {
    let atCenter = try PhotonMeasurementP22.interpolatedSigma(at: PhotonMeasurementP22.binCenter(1), sigma: sSigma, counts: sCounts)
    check("C10.centerExact", abs(atCenter - 0.021) < 1e-12)
    let mid = try PhotonMeasurementP22.interpolatedSigma(at: (PhotonMeasurementP22.binCenter(1) + PhotonMeasurementP22.binCenter(3)) / 2, sigma: sSigma, counts: sCounts)
    check("C11.midInterpolated", abs(mid - 0.022) < 1e-12)
    let low = try PhotonMeasurementP22.interpolatedSigma(at: 0.0, sigma: sSigma, counts: sCounts)
    check("C12.clampLow", abs(low - 0.021) < 1e-12)
    let high = try PhotonMeasurementP22.interpolatedSigma(at: 1.0, sigma: sSigma, counts: sCounts)
    check("C13.clampHigh", high == 0.0)  // nearest supported above range is bin 4 (sigma 0, count 100 -> supported)
} catch { check("C10.interpThrew", false) }
do {
    _ = try PhotonMeasurementP22.interpolatedSigma(at: 0.5, sigma: [Double](repeating: 0.02, count: 8), counts: [Int](repeating: 0, count: 8))
    check("C14.zeroSupportedRefused", false)
} catch PhotonMeasurementP22.MeasurementError.noSupportedBins { check("C14.zeroSupportedRefused", true) }
  catch { check("C14.zeroSupportedRefused", false) }

// -- D. PhotonV4Model handoff behavior ------------------------------------------
do {
    let fallback = try PhotonV4Model.cell(sourceHeight: 1080, outputHeight: 2160, sourceCell: nil, confidence: 0, lookFraction: 0.004, trim: 1)
    check("D1.cellLookFallback", abs(fallback - 8.64) < 1e-9)
    let fitted = try PhotonV4Model.cell(sourceHeight: 1080, outputHeight: 2160, sourceCell: 5, confidence: 0.9, lookFraction: 0.004, trim: 1)
    check("D2.cellSourceFitted", abs(fitted - 10.0) < 1e-9)
    let lowConf = try PhotonV4Model.cell(sourceHeight: 1080, outputHeight: 2160, sourceCell: 5, confidence: 0.5, lookFraction: 0.004, trim: 1)
    check("D3.confidenceGate", abs(lowConf - 8.64) < 1e-9)
    let off = try PhotonV4Model.sigma(target: 0.02, source: 0.01, enabled: false)
    check("D4.sigmaDisabledZero", off == 0)
    let s = try PhotonV4Model.sigma(target: 0.02, source: 0.01)
    check("D5.sigmaCompose", s > 0 && s.isFinite)
} catch { check("D0.modelThrew", false) }

// -- E. Canonical stage order ----------------------------------------------------
let stages = RenderGraphStage.allCases
check("E1.stageInserted", stages.count == 10)
check("E2.stagePosition", stages.firstIndex(of: .sourceMeasurement) == stages.firstIndex(of: .colorToneMap)! - 1
      && stages.firstIndex(of: .sourceMeasurement) == stages.firstIndex(of: .decode)! + 1)
check("E3.noCPUEncoder", !RenderGraphStage.sourceMeasurement.hasEncoder)
check("E4.routingDigestUnchanged", LookParameterRouting.routingDigest() == 0xc6684e869ace3449)
check("E5.manifestDigestUnchanged", LookParameterTable.manifestDigest() == 0x6c88c1b6baf184b4)
check("E6.encoderOrderUnchanged", RenderGraph.encoderApplicationOrder == [.color, .crop, .control, .hostTransform])

// -- F. Shader-source fence declarations (Metal compile NOT_RUN) -----------------
check("F1.measureKernel", PhotonMeasurementShader.source.contains("kernel void photonSourceMeasure"))
check("F2.reduceKernel", PhotonMeasurementShader.source.contains("kernel void photonSourceReduce"))
check("F3.reduceMinimum", PhotonMeasurementShader.source.contains("count>=32"))
check("F4.applyKernel", PhotonP22ApplyShader.source.contains("kernel void photonP22Apply"))
check("F5.applyMaskRule", PhotonP22ApplyShader.source.contains("c >= 32u") && PhotonP22ApplyShader.source.contains("isfinite"))
check("F6.applyOffsets", PhotonP22ApplyShader.source.contains("extOffset + 32") && PhotonP22ApplyShader.source.contains("extOffset + 64"))

print("FINAL pass=\(pass) fail=\(fail)")
exit(fail == 0 ? 0 : 1)
