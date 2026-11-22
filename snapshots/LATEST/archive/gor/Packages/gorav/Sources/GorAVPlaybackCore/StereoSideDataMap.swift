import Foundation

// B6-STEREO-FFMPEG side-data map (lane: stereo/photon), part of the
// shared caller/decoder implementation on the QUALIFIED v7 transport:
// the pure, Linux-testable mapping from FFmpeg's ALREADY-PARSED stereo
// side-data enums (AVStereo3D / AVSphericalMapping, read by the
// FFmpegSoftwareDecoder carrier) onto spmeta.h field observations.
//
// Contract (all pinned, none invented):
//  - NO SYNTHESIS: this map converts only what FFmpeg actually parsed
//    from the container or codec bitstream. Absent side data produces
//    NO observation (the caller emits nothing; UNSET stays UNSET).
//    Nothing is read from generic title/format text, and nothing is
//    defaulted.
//  - SOURCE/FORMAT ORDINALS are the spmeta.h vocabulary (source 1
//    CONTAINER / 2 TRACK / 3 CODEC / 4 OVERRIDE; format 1 MKV / 2 MP4 /
//    3 H264) and are supplied by the carrier, never decided here. The
//    carrier emits TRACK(2) observations from stream side data and
//    CODEC(3) observations from decoded-frame side data; CONTAINER(1)
//    is caller-fed defaults and OVERRIDE(4) is explicit input, so this
//    map is only ever asked for source 2 or 3.
//  - LAYOUT (spmeta_layout_t, order fixed in spmeta.h, never
//    renumbered): AV_STEREO3D_2D -> MONO, SIDEBYSIDE -> SIDE_BY_SIDE,
//    TOPBOTTOM -> TOP_BOTTOM, FRAMESEQUENCE -> FRAME_SEQUENTIAL,
//    CHECKERBOARD -> CHECKERBOARD, LINES -> ROW_INTERLEAVED, COLUMNS ->
//    COLUMN_INTERLEAVED. AV_STEREO3D_SIDEBYSIDE_QUINCUNX has NO spmeta
//    ordinal and is NEVER folded into SIDE_BY_SIDE silently: it becomes
//    kind UNKNOWN with the wire value preserved verbatim in raw. Any
//    other wire value is likewise UNKNOWN with raw preserved.
//  - EYE ORDER (spmeta_eye_order_t, NO-GUESSING): FFmpeg's normalized
//    AVStereo3D erases whether "left first" was explicitly encoded
//    (Matroska StereoMode 1) or merely unspecified (H.264 SEI
//    content_interpretation_type 0), so an unset AV_STEREO3D_FLAG_INVERT
//    is NOT evidence of an explicit left-first encoding. This map emits
//    an eye-order observation ONLY for the explicit inverted case
//    (RIGHT_FIRST). An explicit left-first distinction requires the
//    spmeta parser (ABI PROPOSED, integrator pin pending); until then
//    the asymmetry is deliberate and documented, not a guess.
//  - PROJECTION (spmeta_projection_t): the spmeta enum deliberately
//    carries no 180/360 discrimination; AV_SPHERICAL_EQUIRECTANGULAR and
//    AV_SPHERICAL_HALF_EQUIRECTANGULAR both map to EQUIRECT, and the
//    180/360 layout int stays with session authority. ABSENT spherical
//    side data means UNSET (the carrier emits nothing) - absence is
//    never mapped to FLAT. CUBEMAP maps to CUBEMAP;
//    AV_SPHERICAL_EQUIRECTANGULAR_TILE has no spmeta ordinal and is
//    preserved verbatim as kind UNKNOWN. Any other wire value is
//    likewise UNKNOWN with raw preserved.
//  - FFmpeg wire values arrive as Int32 so this file stays free of any
//    CFFmpeg dependency (Linux-testable); the carrier's FFI reads are
//    the only untestable part and live in the decoder.
//
// INERT until the shared decoder carrier calls it; App registration is
// owned elsewhere (Ops).

public enum StereoSideDataMap {

    /// One decoded stereo3d side-data read mapped to spmeta vocabulary.
    /// `layout` is always emitted (KNOWN when the wire value has an
    /// ordinal, otherwise UNKNOWN with raw preserved). `eyeOrder` is
    /// non-nil ONLY for an explicit inverted (right-first) encoding -
    /// see the file header for the no-guessing rationale.
    public static func mapStereo3D(type: Int32, inverted: Bool,
                                   source: Int, format: Int)
        -> (layout: SpmetaFieldObs, eyeOrder: SpmetaFieldObs?) {
        // AVStereo3DType wire values (FFmpeg 8 libavutil/stereo3d.h):
        // 0 2D, 1 SIDEBYSIDE, 2 TOPBOTTOM, 3 FRAMESEQUENCE,
        // 4 CHECKERBOARD, 5 SIDEBYSIDE_QUINCUNX, 6 LINES, 7 COLUMNS.
        let layout: SpmetaFieldObs
        switch type {
        case 0: // AV_STEREO3D_2D
            layout = SpmetaFieldObs(kind: 1, norm: 1, raw: 0, source: source, format: format)
        case 1: // AV_STEREO3D_SIDEBYSIDE
            layout = SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: source, format: format)
        case 2: // AV_STEREO3D_TOPBOTTOM
            layout = SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: source, format: format)
        case 3: // AV_STEREO3D_FRAMESEQUENCE
            layout = SpmetaFieldObs(kind: 1, norm: 4, raw: 0, source: source, format: format)
        case 4: // AV_STEREO3D_CHECKERBOARD
            layout = SpmetaFieldObs(kind: 1, norm: 7, raw: 0, source: source, format: format)
        case 6: // AV_STEREO3D_LINES
            layout = SpmetaFieldObs(kind: 1, norm: 5, raw: 0, source: source, format: format)
        case 7: // AV_STEREO3D_COLUMNS
            layout = SpmetaFieldObs(kind: 1, norm: 6, raw: 0, source: source, format: format)
        default: // 5 QUINCUNX and every unrecognized wire value
            let raw = UInt32(bitPattern: type)
            layout = SpmetaFieldObs(kind: 2, norm: 0, raw: raw, source: source, format: format)
        }
        let eyeOrder: SpmetaFieldObs? = inverted
            ? SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: source, format: format)
            : nil
        return (layout, eyeOrder)
    }

    /// One decoded spherical-mapping side-data read mapped to the spmeta
    /// projection field. KNOWN when the wire value has an ordinal,
    /// otherwise UNKNOWN with the wire value preserved verbatim in raw.
    /// 180/360 discrimination is deliberately NOT produced here (session
    /// authority owns it).
    public static func mapSpherical(projection: Int32, source: Int, format: Int) -> SpmetaFieldObs {
        // AVSphericalProjection wire values (FFmpeg 8 libavutil/spherical.h):
        // 0 EQUIRECTANGULAR, 1 CUBEMAP, 2 EQUIRECTANGULAR_TILE,
        // 3 HALF_EQUIRECTANGULAR.
        switch projection {
        case 0, 3: // equirect / half-equirect; 180/360 stays session-side
            return SpmetaFieldObs(kind: 1, norm: 2, raw: 0, source: source, format: format)
        case 1: // cubemap
            return SpmetaFieldObs(kind: 1, norm: 3, raw: 0, source: source, format: format)
        default: // 2 tiled equirect and every unrecognized wire value
            return SpmetaFieldObs(kind: 2, norm: 0, raw: UInt32(bitPattern: projection),
                                  source: source, format: format)
        }
    }
}
