public enum PhotonP22ApplyShader {
    /// DR-0017: same-command-buffer P22 measurement apply. Reads the 64-byte
    /// GPU stats ticket (sigma 8 x float @0, counts 8 x uint @32 - the wire
    /// pinned by PhotonMeasurementP22 in GorAVPlaybackCore) and writes the
    /// 72-byte P22 measurement extension at a caller-declared offset: sigma
    /// words (unsupported bins zeroed), measured count words, the validity
    /// mask word, a zero reserved word. Runs ONLY inside the ticket's own
    /// command buffer, fenced by PhotonP22UpdateConsumer before encoding.
    public static let source = #"""
#include <metal_stdlib>
using namespace metal;
// Offsets mirror PhotonMeasurementP22: sigma@0 counts@32 mask@64 reserved@68.
kernel void photonP22Apply(device const uchar* stats [[buffer(0)]],
                           device uchar* p22 [[buffer(1)]],
                           constant uint& extOffset [[buffer(2)]],
                           uint bin [[thread_position_in_grid]]) {
    if (bin >= 8) return;
    device const float* sigma = (device const float*)(stats + 0);
    device const uint* counts = (device const uint*)(stats + 32);
    device float* outSigma = (device float*)(p22 + extOffset);
    device uint* outCounts = (device uint*)(p22 + extOffset + 32);
    device uint* outMask = (device uint*)(p22 + extOffset + 64);
    device uint* outReserved = (device uint*)(p22 + extOffset + 68);
    float s = sigma[bin];
    uint c = counts[bin];
    bool ok = isfinite(s) && s >= 0.0f && c >= 32u;
    outSigma[bin] = ok ? s : 0.0f;  // missing bin = zeroed sigma, mask bit clear
    outCounts[bin] = c;             // measured count always carried (telemetry)
    if (bin == 0) {
        uint m = 0;
        for (uint i = 0; i < 8; i++) {
            float si = sigma[i];
            uint ci = counts[i];
            if (isfinite(si) && si >= 0.0f && ci >= 32u) m |= (1u << i);
        }
        *outMask = m;
        *outReserved = 0;
    }
}
"""# + "\n"
}
