#include <metal_stdlib>
using namespace metal;

// P-B3: Metal implementation of the P-B3 tone-map pipeline.
// Mirrors ScalarHDRReference (Swift, Double) in single-precision float.
// Parity requirement: max absolute channel error vs the CPU reference
// <= 1e-4 (see Tests/HDRReferenceTests/HDRReferenceTests.swift).
// Constants are the published values cited in spec/SPEC.md.

constant float PQ_M1 = 2610.0f / 16384.0f;
constant float PQ_M2 = 2523.0f / 4096.0f * 128.0f;
constant float PQ_C1 = 3424.0f / 4096.0f;
constant float PQ_C2 = 2413.0f / 4096.0f * 32.0f;
constant float PQ_C3 = 2392.0f / 4096.0f * 32.0f;
constant float PQ_PEAK_NITS = 10000.0f;

// BT.2020 -> BT.709 matrix derived from published primaries (spec/SPEC.md 4).
constant float3x3 M_2020_TO_709 = float3x3(
    float3( 1.6604910021084338f, -0.12455047452159063f, -0.018150763354905213f),
    float3(-0.58764113878854973f,  1.1328998971259601f,  -0.10057889800800743f),
    float3(-0.072849863319884856f, -0.0083494226043694872f, 1.1187296613629127f));

float pqEOTF(float n) {
    float nc = clamp(n, 0.0f, 1.0f);
    float p = pow(nc, 1.0f / PQ_M2);
    float num = max(p - PQ_C1, 0.0f);
    float den = PQ_C2 - PQ_C3 * p;
    return PQ_PEAK_NITS * pow(num / den, 1.0f / PQ_M1);
}

float bt709OETF(float l) {
    if (l < 0.018f) {
        return 4.5f * l;
    }
    return 1.099f * pow(l, 0.45f) - 0.099f;
}

/// Map one PQ-encoded BT.2020 pixel to encoded BT.709 SDR.
/// Equivalent inputs/output to ScalarHDRReference.map:
/// input pq2020 encoded [0,1], output float3 encoded BT.709 [0,1].
float3 toneMapPQ2020toBT709(float3 pq2020, float sourcePeakNits, float targetPeakNits) {
    float3 l = float3(pqEOTF(pq2020.r), pqEOTF(pq2020.g), pqEOTF(pq2020.b));
    float y = dot(l, float3(0.2627f, 0.6780f, 0.0593f));
    float yn = y / sourcePeakNits;
    float yt = yn / (1.0f + yn); // Reinhard 2002 global operator
    float lt = yt * targetPeakNits;
    float s = y > 0.0f ? lt / y : 0.0f;
    float3 m = l * s;
    float3 c709 = M_2020_TO_709 * m;
    float3 v = clamp(c709 / targetPeakNits, 0.0f, 1.0f);
    return float3(bt709OETF(v.r), bt709OETF(v.g), bt709OETF(v.b));
}

kernel void toneMapKernel(device const float3 *input [[buffer(0)]],
                          device float3 *output [[buffer(1)]],
                          constant float &sourcePeakNits [[buffer(2)]],
                          constant float &targetPeakNits [[buffer(3)]],
                          uint gid [[thread_position_in_grid]]) {
    output[gid] = toneMapPQ2020toBT709(input[gid], sourcePeakNits, targetPeakNits);
}
