import Foundation
#if canImport(Metal)
import Metal

/// 190t E/F/G: VR180 / SBS eye render on the GPU. Mirrors tools/vr180_render_ref.py op for op (Tests/Stereo3DKernel keeps a Python model of
/// every kernel below). 3D-mode only: nothing in flat playback creates or calls this. The Metal source is compiled at runtime with fast-math
/// off, so a compile or device failure returns nil from `make()` and the caller stays on the 2D path; it cannot break the app build.
enum Stereo3DKernelSource {
    static let text = """
    #include <metal_stdlib>
    using namespace metal;
    struct S3DParams { float f; float eye; uint w; uint h; uint ow; uint oh; float conv; float znear; uint mode; float fout; };   // s36: mode 0 = equirect180 (vr180), 1 = perspective (flat modes, fout = pixels per tan across the eye canvas)
    constant uint S3D_INF = 0x7F800000u;
    static bool s3d_map(uint2 g, constant S3DParams& p, float z, thread int2& o) {
        float rx = ((float)g.x + 0.5f - (float)p.w * 0.5f) / p.f;
        float ry = ((float)p.h * 0.5f - ((float)g.y + 0.5f)) / p.f;
        float px = rx * z - p.eye, py = ry * z, pz = z;
        if (p.mode == 1u) {          // parallel-shift convergence: no toe-in keystone or vertical parallax
            if (!(z > 0.0f)) return false;
            float uu = px / pz + tan(p.conv), vv = py / pz;
            o = int2((int)floor(uu * p.fout + (float)p.ow * 0.5f), (int)floor((float)p.oh * 0.5f - vv * p.fout));
            return o.x >= 0 && o.x < (int)p.ow && o.y >= 0 && o.y < (int)p.oh;
        }
        float n = sqrt(px * px + py * py + pz * pz);
        float lon = atan2(px, pz) + p.conv, lat = asin(py / n);
        float u = lon / M_PI_F + 0.5f, v = 0.5f - lat / M_PI_F;
        o = int2((int)floor(u * (float)p.ow), (int)floor(v * (float)p.oh));
        return z > 0.0f && o.x >= 0 && o.x < (int)p.ow && o.y >= 0 && o.y < (int)p.oh;
    }
    kernel void s3d_clear(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                          texture2d<float, access::write> rendered [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        atomic_store_explicit(&zb[gid.y * p.ow + gid.x], S3D_INF, memory_order_relaxed);
        rendered.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid);
    }
    kernel void s3d_zmin(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                         texture2d<float, access::read> depth [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.w || gid.y >= p.h) return;
        float z = depth.read(gid).r; if (z > 0.0f) z = max(z, p.znear); int2 o;
        if (!s3d_map(gid, p, z, o)) return;
        atomic_fetch_min_explicit(&zb[(uint)o.y * p.ow + (uint)o.x], as_type<uint>(z), memory_order_relaxed);
    }
    kernel void s3d_resolve(device atomic_uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]],
                            texture2d<float, access::read> frame [[texture(0)]], texture2d<float, access::read> depth [[texture(1)]],
                            texture2d<float, access::write> rendered [[texture(2)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.w || gid.y >= p.h) return;
        float z = depth.read(gid).r; if (z > 0.0f) z = max(z, p.znear); int2 o;
        if (!s3d_map(gid, p, z, o)) return;
        if (atomic_load_explicit(&zb[(uint)o.y * p.ow + (uint)o.x], memory_order_relaxed) != as_type<uint>(z)) return;
        rendered.write(float4(frame.read(gid).rgb, 1.0f), uint2(o));
    }
    // F1 integer-exact blend and far-column average; r2 edge-run fill stays inside the frustum.
    constant uint SHORT_RUN_K = 16u, VERT_HALF = 16u;
    static uint4 s3d_codes(float4 c) { return uint4(floor(clamp(c, 0.0f, 1.0f) * 255.0f + 0.5f)); }
    static uint4 s3d_round(uint4 num, uint den) { return (2u * num + den) / (2u * den); }
    static float4 s3d_vavg(device const uint* zb, constant S3DParams& p, texture2d<float, access::read> rendered, uint row, uint col) {
        uint lo = row > VERT_HALF ? row - VERT_HALF : 0u, hi = min(p.oh - 1u, row + VERT_HALF);
        uint4 sum = uint4(0u); uint n = 0u;
        for (uint r = lo; r <= hi; r++) if (zb[r * p.ow + col] != S3D_INF) { sum += s3d_codes(rendered.read(uint2(col, r))); n++; }
        return n > 0u ? float4(s3d_round(sum, n)) / 255.0f : rendered.read(uint2(col, row));
    }
    kernel void s3d_fill(device const uint* zb [[buffer(0)]], constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]],
                         texture2d<float, access::read> rendered [[texture(0)]], texture2d<float, access::write> result [[texture(1)]],
                         uint row [[thread_position_in_grid]]) {
        if (row >= p.oh) return;
        for (uint c0 = 0; c0 < p.ow; c0++) result.write(float4(0.0f), uint2(c0, row));
        int a = -1, first = -1;
        for (uint c = 0; c < p.ow; c++) {
            uint zc = zb[row * p.ow + c];
            if (zc == S3D_INF) continue;
            if (a >= 0 && (int)c - a > 1) {
                uint g = c - (uint)a - 1u;
                if (g <= SHORT_RUN_K) {
                    uint4 A = s3d_codes(rendered.read(uint2((uint)a, row))), B = s3d_codes(rendered.read(uint2(c, row)));
                    for (uint k = 1u; k <= g; k++) result.write(float4(s3d_round(A * (g + 1u - k) + B * k, g + 1u)) / 255.0f, uint2((uint)a + k, row));
                } else {
                    uint za = zb[row * p.ow + (uint)a];
                    uint src = (as_type<float>(za) >= as_type<float>(zc)) ? (uint)a : c;
                    float4 col = s3d_vavg(zb, p, rendered, row, src);
                    for (uint k = (uint)a + 1u; k < c; k++) result.write(col, uint2(k, row));
                }
            }
            result.write(rendered.read(uint2(c, row)), uint2(c, row));
            if (first < 0) first = (int)c;
            a = (int)c;
        }
        if (a < 0) return;
        int lo = -1, hi = -1;
        for (uint c = 0; c < p.ow; c++) if (fp[row * p.ow + c] != 0) { if (lo < 0) lo = (int)c; hi = (int)c; }
        if (lo < 0) return;
        if (first > lo) {
            float4 col = (uint)(first - lo) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)first) : rendered.read(uint2((uint)first, row));
            for (int k = lo; k < first; k++) result.write(col, uint2((uint)k, row));
        }
        if (a < hi) {
            float4 col = (uint)(hi - a) > SHORT_RUN_K ? s3d_vavg(zb, p, rendered, row, (uint)a) : rendered.read(uint2((uint)a, row));
            for (int k = a + 1; k <= hi; k++) result.write(col, uint2((uint)k, row));
        }
    }
    kernel void s3d_depth10(texture2d<float, access::read> luma [[texture(0)]], texture2d<float, access::write> metric [[texture(1)]],
                            constant uint& shift [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= metric.get_width() || gid.y >= metric.get_height()) return;
        uint w10 = (uint)round(luma.read(gid).r * 65535.0f) >> shift;
        float v = (float)w10 / 1023.0f * 1024.0f;
        metric.write(float4(w10 == 0u ? 0.0f : 256.0f / v, 0.0f, 0.0f, 0.0f), gid);
    }
    // s3d_surround r4 (CONTRACT-190v s20 + s28/s28b), four kernels. The footprint mask `fp`, the nearest-footprint extension map `src`, the nearest-footprint (L1 BFS)
    // index `near` and the per-pixel weights `wb` = (t1, t2, wcorr, vert) are content independent and come from SurroundGeometry (CPU, exact port of the reference passes).
    // Colour work is here, float32 textures: 32x normalised 3x3 pre-blur over the footprint (np.roll wrap), gather (outside pixels copy their footprint source, then add the
    // r4 boundary correction (true - preblur32) of their nearest footprint pixel x wcorr; footprint pixels keep the TRUE film colour for the blur windows), clamped boxes
    // (16x16, 96x96 and the side-local far trend 256x64 / 64x256, rx x ry) from separable running sums blended by distance (R1 -> R2 over 1..40 px, R2 -> far over 40..120 px,
    // lerp form), one truncation to uint8. Only canvas OUTSIDE the footprint is written.
    // s31 (d): the pre-blur only matters at footprint pixels (non-footprint neighbours are skipped and gather reads `pre` at footprint pixels only), so the 32 passes are
    // dispatched over the footprint bounding box `box` = (x0, y0, w, h) alone. Exact, not an approximation: nothing outside the box is ever read.
    kernel void s3d_sur_pre(texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]],
                            constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]], constant uint4& box [[buffer(6)]], constant uint& pass0 [[buffer(7)]], uint2 lid [[thread_position_in_grid]]) {
        if (lid.x >= box.z || lid.y >= box.w) return;
        uint2 gid = uint2(box.x + lid.x, box.y + lid.y);
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        if (fp[gid.y * p.ow + gid.x] == 0) { dst.write(float4(0.0f), gid); return; }
        float4 acc = float4(src.read(gid).rgb, 0.0f); float cnt = 1.0f;
        for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
            if (i == 0 && j == 0) continue;
            uint x = (uint)(((int)gid.x + i + (int)p.ow) % (int)p.ow), y = (uint)(((int)gid.y + j + (int)p.oh) % (int)p.oh);
            if (fp[y * p.ow + x] == 0) { if (pass0 != 0) acc += float4(src.read(uint2(x, y)).rgb, 0.0f); continue; }   // pass 0: the reference adds the rendered value of a non-footprint neighbour to the sum (not the count); later passes read 0 there
            acc += float4(src.read(uint2(x, y)).rgb, 0.0f); cnt += 1.0f;
        }
        dst.write(float4(acc.rgb / max(cnt, 1.0f), 1.0f), gid);
    }
    kernel void s3d_sur_gather(texture2d<float, access::read> pre [[texture(0)]], texture2d<float, access::write> work [[texture(1)]], texture2d<float, access::read> truth [[texture(2)]],
                               constant S3DParams& p [[buffer(1)]], device const uchar* fp [[buffer(2)]], device const int* src [[buffer(3)]], device const float4* wb [[buffer(4)]],
                               device const int* near [[buffer(5)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.ow || gid.y >= p.oh) return;
        uint i = gid.y * p.ow + gid.x;
        if (fp[i] != 0) { work.write(float4(truth.read(gid).rgb, 1.0f), gid); return; }          // r4: blur windows read TRUE film content inside the footprint
        int s = src[i];
        if (s < 0) { work.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid); return; }
        float3 v = pre.read(uint2((uint)s % p.ow, (uint)s / p.ow)).rgb;
        int q = near[i];
        if (q >= 0) { uint2 qg = uint2((uint)q % p.ow, (uint)q / p.ow); v += (truth.read(qg).rgb - pre.read(qg).rgb) * wb[i].z; }   // (true - preblur32) x wcorr, additive
        work.write(float4(v, 1.0f), gid);
    }
    // r4 blur: one pass per axis computes the four clamped boxes with running sums (O(1) per pixel; float32 running-sum drift is far below 1 LSB after the divides). Horizontal radii
    // {16, 96, 256, 64}: one thread per row -> four row-blurred textures. Vertical radii {16, 96, 64, 256} for those rows give the rectangles 16x16, 96x96, 256x64 (wide-short, pixels
    // above/below the footprint) and 64x256 (tall-narrow, left/right). One thread per column, then the lerp-form blend and one truncation.
    kernel void s3d_sur_boxh(texture2d<float, access::read> work [[texture(0)]], texture2d<float, access::write> t1 [[texture(1)]], texture2d<float, access::write> t2 [[texture(2)]],
                             texture2d<float, access::write> t3 [[texture(3)]], texture2d<float, access::write> t4 [[texture(4)]], constant S3DParams& p [[buffer(1)]], uint gid [[thread_position_in_grid]]) {
        if (gid >= p.oh) return;
        const int R[4] = {16, 96, 256, 64}; const float D[4] = {33.0f, 193.0f, 513.0f, 129.0f}; const int n = (int)p.ow; float3 s[4];
        for (int k = 0; k < 4; k++) { s[k] = float3(0.0f); for (int i = -R[k]; i <= R[k]; i++) s[k] += work.read(uint2((uint)clamp(i, 0, n - 1), gid)).rgb; }
        for (int x = 0; x < n; x++) {
            t1.write(float4(s[0] / D[0], 1.0f), uint2((uint)x, gid)); t2.write(float4(s[1] / D[1], 1.0f), uint2((uint)x, gid));
            t3.write(float4(s[2] / D[2], 1.0f), uint2((uint)x, gid)); t4.write(float4(s[3] / D[3], 1.0f), uint2((uint)x, gid));
            for (int k = 0; k < 4; k++) s[k] += work.read(uint2((uint)clamp(x + 1 + R[k], 0, n - 1), gid)).rgb - work.read(uint2((uint)clamp(x - R[k], 0, n - 1), gid)).rgb;
        }
    }
    float3 colRead(texture2d<float, access::read> t1, texture2d<float, access::read> t2, texture2d<float, access::read> t3, texture2d<float, access::read> t4, int k, uint x, int y, int n) {
        uint yy = (uint)clamp(y, 0, n - 1);
        return k == 0 ? t1.read(uint2(x, yy)).rgb : (k == 1 ? t2.read(uint2(x, yy)).rgb : (k == 2 ? t3.read(uint2(x, yy)).rgb : t4.read(uint2(x, yy)).rgb));
    }
    kernel void s3d_sur_boxv(texture2d<float, access::read> t1 [[texture(0)]], texture2d<float, access::read> t2 [[texture(1)]], texture2d<float, access::read> t3 [[texture(2)]],
                             texture2d<float, access::read> t4 [[texture(3)]], texture2d<float, access::write> result [[texture(4)]], constant S3DParams& p [[buffer(1)]],
                             device const uchar* fp [[buffer(2)]], device const float4* wb [[buffer(4)]], uint gid [[thread_position_in_grid]]) {
        if (gid >= p.ow) return;
        const int R[4] = {16, 96, 64, 256}; const float D[4] = {33.0f, 193.0f, 129.0f, 513.0f}; const int n = (int)p.oh; float3 s[4];
        for (int k = 0; k < 4; k++) { s[k] = float3(0.0f); for (int j = -R[k]; j <= R[k]; j++) s[k] += colRead(t1, t2, t3, t4, k, gid, j, n); }
        for (int y = 0; y < n; y++) {
            if (fp[(uint)y * p.ow + gid] == 0) {
                float4 w = wb[(uint)y * p.ow + gid]; float3 b1 = s[0] / D[0], b2 = s[1] / D[1], b3 = w.w != 0.0f ? s[2] / D[2] : s[3] / D[3];   // w.w = 1: far trend 256x64 (above/below)
                float3 v = b1 + (b2 - b1) * w.x; v = v + (b3 - v) * w.y;          // lerp form: exact for constant fields
                result.write(float4(floor(v * 255.0f) / 255.0f, 1.0f), uint2(gid, (uint)y));
            }
            for (int k = 0; k < 4; k++) s[k] += colRead(t1, t2, t3, t4, k, gid, y + 1 + R[k], n) - colRead(t1, t2, t3, t4, k, gid, y - R[k], n);
        }
    }
    // s36 packers (output_modes.pack_*): mode 0 side by side, 1 half sbs (2:1 box average per eye, INTER_AREA), 2 over under, 3 Dubois anaglyph (one 3x3 pass on the 0-255 codes, +0.5, clamp, truncate).
    constant float3 DUBOIS_L[3] = {float3(0.437f, 0.449f, 0.164f), float3(-0.062f, -0.062f, -0.024f), float3(-0.048f, -0.050f, -0.017f)};
    constant float3 DUBOIS_R[3] = {float3(-0.011f, -0.032f, -0.007f), float3(0.377f, 0.761f, 0.009f), float3(-0.026f, -0.093f, 1.234f)};
    kernel void s3d_pack(texture2d<float, access::read> left [[texture(0)]], texture2d<float, access::read> right [[texture(1)]],
                         texture2d<float, access::write> outTex [[texture(2)]], constant uint& mode [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        uint ow = left.get_width(), oh = left.get_height();
        if (gid.x >= outTex.get_width() || gid.y >= outTex.get_height()) return;
        if (mode == 1u) {
            uint hw = ow / 2; bool isL = gid.x < hw; uint x = isL ? gid.x : gid.x - hw;
            float3 a = isL ? left.read(uint2(2u * x, gid.y)).rgb : right.read(uint2(2u * x, gid.y)).rgb;
            float3 b = isL ? left.read(uint2(2u * x + 1u, gid.y)).rgb : right.read(uint2(2u * x + 1u, gid.y)).rgb;
            outTex.write(float4((a + b) * 0.5f, 1.0f), gid);
        } else if (mode == 2u) {
            outTex.write(gid.y < oh ? left.read(gid) : right.read(uint2(gid.x, gid.y - oh)), gid);
        } else if (mode == 3u) {
            float3 l = left.read(gid).rgb * 255.0f, r = right.read(gid).rgb * 255.0f;
            float3 a = float3(dot(DUBOIS_L[0], l) + dot(DUBOIS_R[0], r), dot(DUBOIS_L[1], l) + dot(DUBOIS_R[1], r), dot(DUBOIS_L[2], l) + dot(DUBOIS_R[2], r)) + 0.5f;
            outTex.write(float4(floor(clamp(a, 0.0f, 255.0f)) / 255.0f, 1.0f), gid);
        } else {
            outTex.write(gid.x < ow ? left.read(gid) : right.read(uint2(gid.x - ow, gid.y)), gid);
        }
    }
    // s37 passthrough resampling (stereo_probe.place_on_vr180 / vr180_to_perspective). One eye per dispatch. Bilinear in cv2.remap's coordinate convention (map value = pixel INDEX,
    // texel centres at integers), out-of-range taps are black (BORDER_CONSTANT 0) with the remaining weights kept like cv2.
    struct S3DRemap { uint mode; uint srcW; uint srcH; uint outW; uint outH; float f; float thetaOrHFov; };   // mode 0: baked-stereo screen -> vr180 canvas (f = (srcW/2)/tan(theta/2)); mode 1: vr180 equirect eye (srcW = srcH = n) -> perspective (f = (outW/2)/tan(hfov/2))
    static float4 s3d_tap(texture2d<float, access::read> t, int x, int y) {
        if (x < 0 || y < 0 || x >= (int)t.get_width() || y >= (int)t.get_height()) return float4(0.0f);
        return t.read(uint2((uint)x, (uint)y));
    }
    kernel void s3d_remap(texture2d<float, access::read> src [[texture(0)]], texture2d<float, access::write> outTex [[texture(1)]],
                          constant S3DRemap& p [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.outW || gid.y >= p.outH) return;
        float mx, my; bool inside = true;
        if (p.mode == 0u) {
            float n = (float)p.outW;
            float lon = ((float)gid.x + 0.5f) / n * M_PI_F - M_PI_F * 0.5f, lat = M_PI_F * 0.5f - ((float)gid.y + 0.5f) / n * M_PI_F;
            mx = tan(lon) * p.f + (float)p.srcW * 0.5f; my = (float)p.srcH * 0.5f - tan(lat) * p.f;
            inside = mx >= 0.0f && mx < (float)p.srcW && my >= 0.0f && my < (float)p.srcH;
        } else {
            float n = (float)p.srcW;
            float lon = atan(((float)gid.x + 0.5f - (float)p.outW * 0.5f) / p.f), lat = atan(((float)p.outH * 0.5f - (float)gid.y - 0.5f) / p.f);
            mx = (lon + M_PI_F * 0.5f) / M_PI_F * n - 0.5f; my = (M_PI_F * 0.5f - lat) / M_PI_F * n - 0.5f;
        }
        if (!inside) { outTex.write(float4(0.0f, 0.0f, 0.0f, 1.0f), gid); return; }
        int x0 = (int)floor(mx), y0 = (int)floor(my); float fx = mx - (float)x0, fy = my - (float)y0;
        float4 c = (s3d_tap(src, x0, y0) * (1.0f - fx) + s3d_tap(src, x0 + 1, y0) * fx) * (1.0f - fy) + (s3d_tap(src, x0, y0 + 1) * (1.0f - fx) + s3d_tap(src, x0 + 1, y0 + 1) * fx) * fy;
        outTex.write(float4(c.rgb, 1.0f), gid);
    }
    kernel void s3d_sbs(texture2d<float, access::read> left [[texture(0)]], texture2d<float, access::read> right [[texture(1)]],
                        texture2d<float, access::write> sbs [[texture(2)]], uint2 gid [[thread_position_in_grid]]) {
        uint ow = left.get_width(), oh = left.get_height();
        if (gid.x >= ow * 2 || gid.y >= oh) return;
        sbs.write(gid.x < ow ? left.read(gid) : right.read(uint2(gid.x - ow, gid.y)), gid);
    }
    """
}

final class Stereo3DRenderer {
    struct Params { var f: Float; var eye: Float; var w: UInt32; var h: UInt32; var ow: UInt32; var oh: UInt32; var conv: Float; var znear: Float; var mode: UInt32 = 0; var fout: Float = 0 }
    private let device: MTLDevice; let queue: MTLCommandQueue   // queue is internal: RenderShotWriter blits on it so its blits order after render/decodeDepth
    private let clear: MTLComputePipelineState, zmin: MTLComputePipelineState, resolve: MTLComputePipelineState
    private let fill: MTLComputePipelineState, sbs: MTLComputePipelineState
    private var depth10: MTLComputePipelineState?, remapPipe: MTLComputePipelineState?, packPipe: MTLComputePipelineState?
    private(set) var lastCommandBuffer: MTLCommandBuffer?          // s32: the probe waits on it to time one render (render() itself returns after commit)
    private var surroundPipes: [MTLComputePipelineState]?        // s3d_sur_pre, _gather, _boxh, _boxv (CONTRACT-190v s20, s28 r4)
    private var scratch: [MTLTexture] = []                         // rgba32Float ping, pong, work, tmp1-4 (rx = 16/96/256/64 row blurs) for the surround, sized to the canvas
    private var geoBuffers: [ObjectIdentifier: (fp: MTLBuffer, src: MTLBuffer?, wb: MTLBuffer?, near: MTLBuffer?, geo: SurroundGeometry)] = [:]
    private func buffers(_ geo: SurroundGeometry, surround: Bool) -> (fp: MTLBuffer, src: MTLBuffer?, wb: MTLBuffer?, near: MTLBuffer?)? {
        let k = ObjectIdentifier(geo)
        if geoBuffers.count > 8 { geoBuffers.removeAll() }
        var e = geoBuffers[k]
        if e == nil { guard let fp = geo.inside.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }) else { return nil }; e = (fp, nil, nil, nil, geo) }
        if surround, e!.src == nil {
            let idx = geo.sourceIndex, wb = geo.blendWeights, nr = geo.nearIndex
            e!.src = idx.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            e!.wb = wb.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
            e!.near = nr.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        }
        geoBuffers[k] = e; return (e!.fp, e!.src, e!.wb, e!.near)
    }

    /// nil when there is no Metal device or the source does not compile: stay on the 2D path.
    static func make() -> Stereo3DRenderer? {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        let options = MTLCompileOptions(); options.fastMathEnabled = false
        guard let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: options) else { return nil }
        func pipe(_ name: String) -> MTLComputePipelineState? {
            guard let fn = lib.makeFunction(name: name) else { return nil }
            return try? device.makeComputePipelineState(function: fn)
        }
        guard let c = pipe("s3d_clear"), let z = pipe("s3d_zmin"), let r = pipe("s3d_resolve"), let f = pipe("s3d_fill"), let s = pipe("s3d_sbs") else { return nil }
        let renderer = Stereo3DRenderer(device: device, queue: queue, clear: c, zmin: z, resolve: r, fill: f, sbs: s)
        renderer.remapPipe = pipe("s3d_remap")                // s37 passthrough; nil = passthrough returns false
        renderer.packPipe = pipe("s3d_pack")                  // nil = the flat output modes are unavailable (render returns false), vr180 is unaffected
        return renderer
    }
    private init(device: MTLDevice, queue: MTLCommandQueue, clear: MTLComputePipelineState, zmin: MTLComputePipelineState,
                 resolve: MTLComputePipelineState, fill: MTLComputePipelineState, sbs: MTLComputePipelineState) {
        self.device = device; self.queue = queue; self.clear = clear; self.zmin = zmin; self.resolve = resolve; self.fill = fill; self.sbs = sbs
    }

    static func texture(_ device: MTLDevice, _ format: MTLPixelFormat, _ w: Int, _ h: Int) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]; d.storageMode = .private
        return device.makeTexture(descriptor: d)
    }

    /// frame: rgba8/bgra8 source picture, depth: r32Float aligned METRIC depth (metres along the optical axis), thetaH: radians (shot median fov_x).
    /// `swapEyes` puts the +ipd/2 eye in the left half (the vr180-look vr_swap_eyes=1 order); a negative `ipd` does the same and is not needed. Writes side-by-side (left | right) equirect-180 eyes into `sbsOut` (2*outW x outH). Returns false on any resource failure.
    func render(frame: MTLTexture, depth: MTLTexture, thetaH: Double, ipd: Double = 0.063, convergence: Double? = nil, zNear: Double? = nil, swapEyes: Bool = false, surround: Bool = false, outW: Int, outH: Int, sbsOut: MTLTexture, output: OutputMode = .vr180) -> Bool {
        // s36: `output` = vr180 (default, unchanged: equirect180 eyes, outW = outH = eye N, sbsOut 2N x N) or a flat mode (perspective eyes at the source size: outW x outH = frame size,
        // sbsOut = output.canvasSize; no surround, the film fills the frame). Flat modes need the s3d_pack pipeline.
        let flat = output.isFlat, canvas = output.canvasSize(srcW: outW, srcH: outH)
        guard flat ? (sbsOut.width == canvas.w && sbsOut.height == canvas.h && outW == frame.width && outH == frame.height && packPipe != nil && (output != .halfSBS || outW % 2 == 0))
                   : (sbsOut.width == outW * 2 && sbsOut.height == outH),
              depth.width == frame.width, depth.height == frame.height,
              let cb = queue.makeCommandBuffer(),
              let zb = device.makeBuffer(length: outW * outH * 4, options: .storageModePrivate) else { return false }
        let surround = surround && !flat
        if surround, surroundPipes == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil) {
            let ps = ["s3d_sur_pre", "s3d_sur_gather", "s3d_sur_boxh", "s3d_sur_boxv"].compactMap { n in lib.makeFunction(name: n).flatMap { try? device.makeComputePipelineState(function: $0) } }
            surroundPipes = ps.count == 4 ? ps : nil        // nil on failure: the surround stays black, the render still succeeds
        }
        if surround, surroundPipes != nil, scratch.count != 7 || scratch[0].width != outW || scratch[0].height != outH {
            let t = (0..<7).compactMap { _ in Stereo3DRenderer.texture(device, .rgba32Float, outW, outH) }
            scratch = t.count == 7 ? t : []
        }
        var eyes: [MTLTexture] = []
        for sign in (swapEyes ? [1.0, -1.0] : [-1.0, 1.0]) {
            guard let rendered = Stereo3DRenderer.texture(device, .rgba8Unorm, outW, outH),
                  let result = Stereo3DRenderer.texture(device, .rgba8Unorm, outW, outH),
                  let enc = cb.makeComputeCommandEncoder() else { return false }
            let fD = (Double(frame.width) / 2.0) / tan(thetaH / 2.0)
            let convD = convergence.map { $0 > 0 ? atan2(sign * ipd / 2.0, $0) : 0 } ?? 0
            let geo = SurroundGeometry.cached(w: frame.width, h: frame.height, f: fD, conv: Double(Float(convD)), ow: outW, oh: outH)   // Float round trip: the kernel's own conv
            guard let gb = buffers(geo, surround: surround && surroundPipes != nil && scratch.count == 7) else { return false }
            let foutD = (Double(outW) / 2.0) / tan(OutputMode.screenDeg * Double.pi / 360.0)
            // Parallel-shift source frustum, per eye. Do not fill canvas margins with stretched film edges.
            var flatFP: MTLBuffer? = nil
            if flat {
                var mask = [UInt8](repeating: 0, count: outW * outH)
                let shift = tan(Double(Float(convD)))
                for y in 0..<outH { for x in 0..<outW {
                    let u = (Double(x) + 0.5 - Double(outW) / 2) / foutD - shift
                    let v = (Double(outH) / 2 - (Double(y) + 0.5)) / foutD
                    let sx = fD * u + Double(frame.width) / 2, sy = Double(frame.height) / 2 - fD * v
                    if sx >= 0 && sx < Double(frame.width) && sy >= 0 && sy < Double(frame.height) { mask[y * outW + x] = 1 }
                } }
                flatFP = device.makeBuffer(bytes: mask, length: mask.count, options: .storageModeShared)
                guard flatFP != nil else { return false }
            }
            var p = Params(f: Float((Double(frame.width) / 2.0) / tan(thetaH / 2.0)), eye: Float(sign * ipd / 2.0),
                           w: UInt32(frame.width), h: UInt32(frame.height), ow: UInt32(outW), oh: UInt32(outH),
                           conv: convergence.map { $0 > 0 ? Float(atan2(sign * ipd / 2.0, $0)) : 0 } ?? 0,
                           znear: zNear.map { $0 > 0 ? Float($0) : 0 } ?? 0, mode: flat ? 1 : 0, fout: flat ? Float(foutD) : 0)
            let out = MTLSize(width: outW, height: outH, depth: 1), src = MTLSize(width: frame.width, height: frame.height, depth: 1)
            func dispatch(_ s: MTLComputePipelineState, _ grid: MTLSize) {
                enc.setComputePipelineState(s)
                enc.dispatchThreads(grid, threadsPerThreadgroup: MTLSize(width: 16, height: min(16, max(1, grid.height)), depth: 1))
            }
            enc.setBuffer(zb, offset: 0, index: 0); enc.setBytes(&p, length: MemoryLayout<Params>.size, index: 1)
            enc.setTexture(rendered, index: 0); dispatch(clear, out)
            enc.setTexture(depth, index: 0); dispatch(zmin, src)
            enc.setTexture(frame, index: 0); enc.setTexture(depth, index: 1); enc.setTexture(rendered, index: 2); dispatch(resolve, src)
            enc.setTexture(rendered, index: 0); enc.setTexture(result, index: 1); enc.setBuffer(flat ? flatFP : gb.fp, offset: 0, index: 2)
            enc.setComputePipelineState(fill)
            enc.dispatchThreads(MTLSize(width: outH, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outH), height: 1, depth: 1))
            if surround, let ps = surroundPipes, scratch.count == 7, let sb = gb.src, let wb = gb.wb, let nb = gb.near, !geo.allInside {
                // r3 soft surround: normalised pre-blur x32 (canvas -> ping -> pong ...), gather the nearest-footprint source, boundary correction, four running-sum boxes (side-local far trend), distance lerp; outside the footprint only
                enc.setBuffer(gb.fp, offset: 0, index: 2); enc.setBuffer(sb, offset: 0, index: 3); enc.setBuffer(wb, offset: 0, index: 4); enc.setBuffer(nb, offset: 0, index: 5)
                var cur: MTLTexture = result
                var bx = geo.footprintBox; enc.setBytes(&bx, length: MemoryLayout<SIMD4<UInt32>>.size, index: 6)          // s31: pre-blur over the footprint box only
                let preGrid = MTLSize(width: Int(bx[2]), height: Int(bx[3]), depth: 1)
                for k in 0..<32 { var first: UInt32 = k == 0 ? 1 : 0; enc.setBytes(&first, length: 4, index: 7); let dst = scratch[k % 2]; enc.setTexture(cur, index: 0); enc.setTexture(dst, index: 1); dispatch(ps[0], preGrid); cur = dst }
                enc.setTexture(cur, index: 0); enc.setTexture(scratch[2], index: 1); enc.setTexture(result, index: 2); dispatch(ps[1], out)          // work (r4: truth = the filled film in `result`)
                enc.setTexture(scratch[2], index: 0); enc.setTexture(scratch[3], index: 1); enc.setTexture(scratch[4], index: 2); enc.setTexture(scratch[5], index: 3); enc.setTexture(scratch[6], index: 4)
                enc.setComputePipelineState(ps[2]); enc.dispatchThreads(MTLSize(width: outH, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outH), height: 1, depth: 1))   // row boxes
                enc.setTexture(scratch[3], index: 0); enc.setTexture(scratch[4], index: 1); enc.setTexture(scratch[5], index: 2); enc.setTexture(scratch[6], index: 3); enc.setTexture(result, index: 4)
                enc.setComputePipelineState(ps[3]); enc.dispatchThreads(MTLSize(width: outW, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: min(64, outW), height: 1, depth: 1))   // column boxes + blend
            }
            enc.endEncoding(); eyes.append(result)
        }
        guard let enc = cb.makeComputeCommandEncoder() else { return false }
        var packMode = output.packCode
        enc.setComputePipelineState(flat ? packPipe! : sbs); enc.setTexture(eyes[0], index: 0); enc.setTexture(eyes[1], index: 1); enc.setTexture(sbsOut, index: 2)
        if flat { enc.setBytes(&packMode, length: 4, index: 0) }
        enc.dispatchThreads(MTLSize(width: flat ? canvas.w : outW * 2, height: flat ? canvas.h : outH, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: min(16, outH), depth: 1))
        enc.endEncoding(); cb.commit(); lastCommandBuffer = cb
        return true
    }

    /// CONTRACT-190v v2 depth: `luma` is the Y plane of a 10-bit biplanar decode (MTLPixelFormat.r16Unorm view of plane 0, VideoToolbox), `metric`
    /// r32Float same size. Z = 256 / (w10/1023*1024) metres, w10 == 0 -> 0 (masked, skipped by s3d_map). `shift` = bits the decoder left of the 10-bit
    /// value (6 for Apple MSB-aligned 420YpCbCr10BiPlanar, 0 if right-aligned): unverified on device, so it is a parameter, not a guess baked in.
    func decodeDepth(luma: MTLTexture, metric: MTLTexture, shift: UInt32 = 6) -> Bool {
        if depth10 == nil, let lib = try? device.makeLibrary(source: Stereo3DKernelSource.text, options: nil), let fn = lib.makeFunction(name: "s3d_depth10") {
            depth10 = try? device.makeComputePipelineState(function: fn)
        }
        guard let pipe = depth10, luma.width == metric.width, luma.height == metric.height, shift <= 6,
              let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return false }
        var sh = shift
        enc.setComputePipelineState(pipe); enc.setTexture(luma, index: 0); enc.setTexture(metric, index: 1); enc.setBytes(&sh, length: 4, index: 0)
        enc.dispatchThreads(MTLSize(width: metric.width, height: metric.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: min(16, metric.height), depth: 1))
        enc.endEncoding(); cb.commit()
        return true
    }

    /// s37 passthrough of an ALREADY-3D source (no depth stage): `left`/`right` = the eye crops of the source frame (readable rgba8/bgra8; half layouts must be upscaled by the caller first).
    /// Baked-stereo (flat) source: flat output modes are lossless repacks (s3d_pack); vr180 output places each eye as a flat screen on the equirect canvas (s3d_remap mode 0, 75 deg screen).
    /// vr180 source: flat output reprojects the forward 75 deg (s3d_remap mode 1), then packs; vr180 -> vr180 is the source itself (returns false: play the file). `sbsOut` = output.canvasSize.
    /// Mirrors stereo_probe.passthrough (Linux parity of the resampling: Tests/Stereo3DKernel/stereo_remap_kernel_test.py). Not run on a Mac.
    func passthrough(left: MTLTexture, right: MTLTexture, sourceIsVR180: Bool, output: OutputMode, swap: Bool, sbsOut: MTLTexture) -> Bool {
        let needsRemap = output == .vr180 || sourceIsVR180, needsPack = output != .vr180     // review F2: each path needs only its own pipelines (a pack failure must not disable vr180 placement)
        guard left.width == right.width, left.height == right.height, !needsRemap || remapPipe != nil, !needsPack || packPipe != nil,
              !(sourceIsVR180 && output == .vr180), let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return false }
        let eyes = swap ? [right, left] : [left, right]
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        func remap(_ src: MTLTexture, _ dst: MTLTexture, mode: UInt32, f: Double) {
            var rm = S3DRemapParams(mode: mode, srcW: UInt32(src.width), srcH: UInt32(src.height), outW: UInt32(dst.width), outH: UInt32(dst.height), f: Float(f), thetaOrHFov: 0)
            enc.setComputePipelineState(remapPipe!); enc.setTexture(src, index: 0); enc.setTexture(dst, index: 1); enc.setBytes(&rm, length: MemoryLayout<S3DRemapParams>.size, index: 0)
            enc.dispatchThreads(MTLSize(width: dst.width, height: dst.height, depth: 1), threadsPerThreadgroup: tg)
        }
        let half = tan(OutputMode.screenDeg * Double.pi / 360.0)
        var out: [MTLTexture] = []
        if output == .vr180 {
            let n = sbsOut.height, f = (Double(left.width) / 2.0) / half
            guard sbsOut.width == 2 * n else { enc.endEncoding(); return false }
            for e in eyes { guard let t = Stereo3DRenderer.texture(device, .rgba8Unorm, n, n) else { enc.endEncoding(); return false }; remap(e, t, mode: 0, f: f); out.append(t) }
            enc.setComputePipelineState(sbs); enc.setTexture(out[0], index: 0); enc.setTexture(out[1], index: 1); enc.setTexture(sbsOut, index: 2)
            enc.dispatchThreads(MTLSize(width: 2 * n, height: n, depth: 1), threadsPerThreadgroup: tg)
        } else {
            let ew: Int, eh: Int
            if sourceIsVR180 { (ew, eh) = (output.eyeW(canvasW: sbsOut.width), output.eyeH(canvasH: sbsOut.height)) } else { (ew, eh) = (left.width, left.height) }
            let c = output.canvasSize(srcW: ew, srcH: eh)
            guard c.w == sbsOut.width, c.h == sbsOut.height, output != .halfSBS || ew % 2 == 0 else { enc.endEncoding(); return false }
            for e in eyes {
                if sourceIsVR180 {
                    guard let t = Stereo3DRenderer.texture(device, .rgba8Unorm, ew, eh) else { enc.endEncoding(); return false }
                    remap(e, t, mode: 1, f: (Double(ew) / 2.0) / half); out.append(t)
                } else { out.append(e) }
            }
            var pm = output.packCode
            enc.setComputePipelineState(packPipe!); enc.setTexture(out[0], index: 0); enc.setTexture(out[1], index: 1); enc.setTexture(sbsOut, index: 2); enc.setBytes(&pm, length: 4, index: 0)
            enc.dispatchThreads(MTLSize(width: c.w, height: c.h, depth: 1), threadsPerThreadgroup: tg)
        }
        enc.endEncoding(); cb.commit(); lastCommandBuffer = cb
        return true
    }
}
struct S3DRemapParams { var mode: UInt32; var srcW: UInt32; var srcH: UInt32; var outW: UInt32; var outH: UInt32; var f: Float; var thetaOrHFov: Float }   // = MSL S3DRemap (7 x 4 bytes)
#endif
