/* AUTHORED_R2 replacement (2026-10-16, ZDYM provider/build lane).
 * NOT the pinned r1 member (pin 3114B/562aa5ad...); byte identity is not claimed.
 * Role per DECODER-ONLY-TARGET-WIRING-r1: avformat/avcodec/avutil/frame/pixdesc/imgutils/buffer/mem
 * imports, error constants, frame classification, interrupt callback bridge.
 * Provider lock (P1): FFmpeg 8.0.1 @ 894da5ca7d742e4429ffb2af534fcda0103ef593,
 * private-prefix headers only. No system/Homebrew FFmpeg.
 *
 * AUTHORED_L3 extension (2026-10-25, L3 formats/hardware-decode lane):
 * the AUTHORED_R2 body below is preserved verbatim; the L3 section after the
 * marker adds swscale/swresample imports, VideoToolbox hwcontext (Darwin),
 * measured-fallback hardware state, yuv420p conversion and s16le-stereo
 * resample helpers. Static inline only; no new translation unit. */
#ifndef GORAV_CFFMPEG_SHIM_H
#define GORAV_CFFMPEG_SHIM_H

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/frame.h>
#include <libavutil/pixdesc.h>
#include <libavutil/imgutils.h>
#include <libavutil/buffer.h>
#include <libavutil/mem.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

/* Current AVIO input buffer occupancy, not decoded cache or playable time.
 * No read, refill, seek or I/O side effect. -1 means unavailable/inconsistent. */
static inline int64_t gorav_avio_buffer_available(const AVIOContext *io) {
    if (!io || io->write_flag || !io->buffer || !io->buf_ptr || !io->buf_end || io->buffer_size < 0) return -1;
    uintptr_t base = (uintptr_t)io->buffer, p = (uintptr_t)io->buf_ptr, end = (uintptr_t)io->buf_end;
    if (p < base || end < p || end - base > (uint64_t)io->buffer_size) return -1;
    return (int64_t)(end - p);
}

/* Error constants: stable negative AVERROR values surfaced to Swift as ints. */
static inline int gorav_av_error_open(int code) { return code; } /* identity, keeps call site explicit */
static inline int gorav_av_errbuf(int code, char *dst, int dst_size) {
    if (dst == NULL || dst_size <= 0) { return -1; }
    if (av_strerror(code, dst, (size_t)dst_size) < 0) { dst[0] = '\0'; return -1; }
    return 0;
}
static inline int gorav_av_err_eof(void) { return AVERROR_EOF; }
static inline int gorav_av_err_exit(void) { return AVERROR_EXIT; }
static inline int gorav_av_err_eagain(void) { return AVERROR(EAGAIN); }

/* Frame classification for the decoder-only probe. UNKNOWN is a real value;
 * classification is reported, never inferred beyond codec/frame facts. */
enum GorAVFrameClass {
    GORAV_FRAME_CLASS_UNKNOWN = 0,
    GORAV_FRAME_CLASS_VIDEO_KEY = 1,
    GORAV_FRAME_CLASS_VIDEO_DELTA = 2,
    GORAV_FRAME_CLASS_OTHER = 3
};
static inline enum GorAVFrameClass gorav_classify_frame(const AVFrame *f) {
    if (f == NULL) { return GORAV_FRAME_CLASS_UNKNOWN; }
    if (f->flags & AV_FRAME_FLAG_KEY) { return GORAV_FRAME_CLASS_VIDEO_KEY; }
    if (f->width > 0 && f->height > 0) { return GORAV_FRAME_CLASS_VIDEO_DELTA; }
    return GORAV_FRAME_CLASS_OTHER;
}

/* Interrupt callback bridge: ioOnly capability. Aborts blocking demux/AVIO calls
 * that poll this callback; does NOT interrupt a stuck decode. */
typedef int (*GorAVInterruptPoll)(void *opaque);
struct GorAVInterruptSlot {
    GorAVInterruptPoll poll; /* returns nonzero to request abort */
    void *opaque;
};
static inline int gorav_avio_interrupt_thunk(void *opaque) {
    struct GorAVInterruptSlot *slot = (struct GorAVInterruptSlot *)opaque;
    if (slot == NULL || slot->poll == NULL) { return 0; }
    return slot->poll(slot->opaque);
}

/* Produce actual digital silence in the decoded frame's own sample format.
 * Caller converts it through the SAME resampler before the real next frame. */
static inline AVFrame *gorav_audio_gap_silence(const AVFrame *reference, int samples) {
    if (!reference || samples <= 0 || samples > 96000) return NULL;
    AVFrame *silence = av_frame_alloc();
    if (!silence) return NULL;
    silence->format = reference->format;
    silence->sample_rate = reference->sample_rate;
    silence->nb_samples = samples;
    if (av_channel_layout_copy(&silence->ch_layout, &reference->ch_layout) < 0 ||
        av_frame_get_buffer(silence, 0) < 0 ||
        av_samples_set_silence(silence->extended_data, 0, samples,
            silence->ch_layout.nb_channels, (enum AVSampleFormat)silence->format) < 0) {
        av_frame_free(&silence); return NULL;
    }
    return silence;
}

/* Version labels are diagnostics only, never byte identity or ABI proof. */
static inline unsigned gorav_avformat_version(void) { return avformat_version(); }
static inline unsigned gorav_avcodec_version(void) { return avcodec_version(); }
static inline unsigned gorav_avutil_version(void) { return avutil_version(); }

/* Authored successor: pinned-source custom IO ownership, NOT importer-tested. */
static inline int gorav_av_err_einval(void) { return AVERROR(EINVAL); }
/* AV_NOPTS_VALUE macro is not importable by Swift; expose it as a function. */
static inline int64_t gorav_av_nopts_value(void) { return AV_NOPTS_VALUE; }
static inline void gorav_free_custom_avio(AVIOContext **io) {
    if (!io || !*io) return;
    av_freep(&(*io)->buffer); /* CURRENT buffer, never original stale pointer */
    avio_context_free(io);
}
static inline void gorav_bind_custom_avio(AVFormatContext *format, AVIOContext *io) {
    format->pb = io;
    format->flags |= AVFMT_FLAG_CUSTOM_IO;
}

/* =================== AUTHORED_L3 section begins ===================
 * L3 formats/hardware-decode lane. Everything in this section is new. */

#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/hwcontext.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <libavutil/opt.h>
#include <libavutil/mastering_display_metadata.h>
#if defined(__APPLE__)
#include <libavutil/hwcontext_videotoolbox.h>
#endif

static inline unsigned gorav_l3_swscale_version(void) { return swscale_version(); }
static inline unsigned gorav_l3_swresample_version(void) { return swresample_version(); }

/* Decoder-presence probe: lets tests assert the built binary actually contains
 * a decoder instead of trusting the configure line. Returns 1 if present. */
static inline int gorav_l3_has_decoder(const char *name) {
    return avcodec_find_decoder_by_name(name) != NULL ? 1 : 0;
}

/* --- Hardware decode (VideoToolbox, Darwin) with measured fallback --- */

/* Mutable receipt slot. Lives on the Swift side (heap-allocated, stable address);
 * the get_format callback reads/writes it through AVCodecContext.opaque. */
struct GorAVL3HWState {
    int hw_attempted;        /* 1 once VT attach was requested */
    int hw_active;           /* 1 if the decoder negotiated a VT format */
    int hw_frames;           /* frames received carrying AV_PIX_FMT_VIDEOTOOLBOX */
    int hw_transfer_errors;  /* failed av_hwframe_transfer_data calls */
    int hw_disabled;         /* 1 once this session fell back to software */
};

static enum AVPixelFormat gorav_l3_get_format_vt(struct AVCodecContext *s,
                                                 const enum AVPixelFormat *fmt) {
    struct GorAVL3HWState *st = (struct GorAVL3HWState *)s->opaque;
    const enum AVPixelFormat *p;
    enum AVPixelFormat first_sw = AV_PIX_FMT_NONE;
    for (p = fmt; *p != AV_PIX_FMT_NONE; p++) {
        const AVPixFmtDescriptor *d;
        if (*p == AV_PIX_FMT_VIDEOTOOLBOX) {
            if (st != NULL && !st->hw_disabled) {
                st->hw_active = 1;
                return AV_PIX_FMT_VIDEOTOOLBOX;
            }
            continue;
        }
        /* Software candidate must be a REAL software format: skip any other
         * hwaccel pixel format the list may carry. */
        d = av_pix_fmt_desc_get(*p);
        if (d != NULL && (d->flags & AV_PIX_FMT_FLAG_HWACCEL)) { continue; }
        if (first_sw == AV_PIX_FMT_NONE) { first_sw = *p; }
    }
    if (st != NULL) { st->hw_active = 0; }
    return first_sw != AV_PIX_FMT_NONE ? first_sw : AV_PIX_FMT_NONE;
}

/* Attaches a VideoToolbox device context and the get_format bridge.
 * Returns 0 on attach, -1 if VT device creation failed, -2 off-Darwin. */
static inline int gorav_l3_attach_videotoolbox(AVCodecContext *ctx, struct GorAVL3HWState *st) {
#if defined(__APPLE__)
    AVBufferRef *dev = NULL;
    if (av_hwdevice_ctx_create(&dev, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, NULL, NULL, 0) < 0) {
        return -1;
    }
    ctx->hw_device_ctx = dev; /* ownership transferred; freed with ctx */
    ctx->get_format = gorav_l3_get_format_vt;
    ctx->opaque = st;
    if (st != NULL) { st->hw_attempted = 1; }
    return 0;
#else
    (void)ctx; (void)st;
    return -2;
#endif
}

/* Detach: disarm the callback and drop the device ref so a software-only
 * retry of the same codec context is honest. */
static inline void gorav_l3_detach_hardware(AVCodecContext *ctx, struct GorAVL3HWState *st) {
    if (st != NULL) { st->hw_disabled = 1; st->hw_active = 0; }
    if (ctx != NULL) {
        ctx->get_format = NULL;
        ctx->opaque = NULL;
        av_buffer_unref(&ctx->hw_device_ctx);
    }
}

/* Transfers one hardware frame to a software frame, copying metadata. */
static inline int gorav_l3_hw_transfer(AVFrame *dst_sw, const AVFrame *src_hw,
                                       struct GorAVL3HWState *st) {
    int ret = av_hwframe_transfer_data(dst_sw, src_hw, 0);
    if (ret < 0) { if (st != NULL) { st->hw_transfer_errors++; } return ret; }
    /* v4: props copy is checked - a silent failure here was a side-data
     * LOSS on the transferred frame (HDR metadata gone with no record). */
    ret = av_frame_copy_props(dst_sw, src_hw);
    if (ret < 0) { if (st != NULL) { st->hw_transfer_errors++; } return ret; }
    if (st != NULL) { st->hw_frames++; }
    return 0;
}

static inline int gorav_l3_pixfmt_videotoolbox(void) { return (int)AV_PIX_FMT_VIDEOTOOLBOX; }

/* --- Pixel conversion: any admitted software frame -> YUV420P 8-bit --- */

struct GorAVL3PixConv {
    struct SwsContext *ctx;
    enum AVPixelFormat src_fmt;
    int src_w;
    int src_h;
    /* v4: colorspace/range join the cache key - a color-only change on the
     * same geometry previously kept a STALE conversion matrix. */
    int src_range;
    int src_csp;
};

/* v4: aggregate byte budget for one derived frame (bounds the 16k alloc). */
#define GORAV_L3_MAX_CONVERT_BYTES (64 << 20)

static inline struct GorAVL3PixConv *gorav_l3_pixconv_open(void) {
    return (struct GorAVL3PixConv *)calloc(1, sizeof(struct GorAVL3PixConv));
}

static inline void gorav_l3_pixconv_close(struct GorAVL3PixConv **pc) {
    if (pc == NULL || *pc == NULL) { return; }
    if ((*pc)->ctx != NULL) { sws_freeContext((*pc)->ctx); }
    free(*pc);
    *pc = NULL;
}

/* v4.4 repair (r6 g6): EXACT av_frame_get_buffer(align 32) allocation
 * model for a yuv420p destination of w x h - ceil chroma widths, the
 * linesize alignment loop, 32-row padded height, plane sizes, and the
 * per-buffer alignment overhead measured once against the REAL allocator
 * (so the value tracks the running build's ALIGN/plane-padding exactly).
 * Returns -1 when the geometry is not computable. The old floor(width/2)
 * estimate was not a bound: odd widths understate the chroma planes and
 * no padding was modeled (65x1: estimate 160 B vs actual 5376 B
 * allocation - geometry-check.c). */
static inline int64_t gorav_l3_yuv420p_alloc_estimate(int32_t w, int32_t h) {
    int ls[4] = {0, 0, 0, 0};
    ptrdiff_t pls[4];
    size_t sizes[4] = {0, 0, 0, 0};
    int i, ph;
    int64_t payload;
    static int64_t overhead = -1;
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384) { return -1; }
    /* libavutil/frame.c get_video_buffer: smallest power-of-two width
     * alignment whose y linesize is a multiple of 32, then 32-align. */
    for (i = 1; i <= 32; i += i) {
        if (av_image_fill_linesizes(ls, AV_PIX_FMT_YUV420P, (w + i - 1) & ~(i - 1)) < 0) { return -1; }
        if (!(ls[0] & 31)) { break; }
    }
    for (i = 0; i < 4 && ls[i]; i++) { ls[i] = (ls[i] + 31) & ~31; }
    ph = (h + 31) & ~31;
    for (i = 0; i < 4; i++) { pls[i] = ls[i]; }
    if (av_image_fill_plane_sizes(sizes, AV_PIX_FMT_YUV420P, ph, pls) < 0) { return -1; }
    payload = (int64_t)sizes[0] + (int64_t)sizes[1] + (int64_t)sizes[2] + (int64_t)sizes[3];
    if (overhead < 0) {
        /* per-buffer overhead (4*plane_padding + 4*align) is
         * geometry-independent: measure once with a 1x1 frame whose
         * modeled payload is 32*32 + 2*(32*16) = 2048. */
        AVFrame *t = av_frame_alloc();
        if (t == NULL) { return -1; }
        t->format = AV_PIX_FMT_YUV420P; t->width = 1; t->height = 1;
        if (av_frame_get_buffer(t, 32) < 0 || t->buf[0] == NULL) { av_frame_free(&t); return -1; }
        overhead = (int64_t)t->buf[0]->size - 2048;
        av_frame_free(&t);
        if (overhead < 0) { return -1; }
    }
    return payload + overhead;
}

/* Converts src into dst as YUV420P 8-bit at source size, EXPLICIT bt709
 * coefficients and range handling (no ambient defaults). ALL bounds are
 * validated BEFORE any allocation or read: geometry, software-only format,
 * positive strides. sws_scale must return the FULL output row count; a
 * partial scale is an error, not a quiet short frame. dst metadata copy is
 * checked. src must already be a software frame (transfer hw frames first). */
static inline int gorav_l3_to_yuv420p(struct GorAVL3PixConv *pc, AVFrame *dst, const AVFrame *src) {
    int ret, i;
    const int *coeffs;
    int src_range;
    const AVPixFmtDescriptor *d;
    if (pc == NULL || dst == NULL || src == NULL) { return AVERROR(EINVAL); }
    if (src->width <= 0 || src->height <= 0 || src->width > 16384 || src->height > 16384) {
        return AVERROR(EINVAL);
    }
    d = av_pix_fmt_desc_get((enum AVPixelFormat)src->format);
    if (d == NULL || (d->flags & AV_PIX_FMT_FLAG_HWACCEL)) { return AVERROR(EINVAL); }
    for (i = 0; i < 8; i++) {
        if (src->data[i] != NULL && src->linesize[i] <= 0) { return AVERROR(EINVAL); }
    }
    /* v4: per-plane minimum strides + refcounted-buffer coverage BEFORE any
     * read (the Swift-side lease check covers the retained frame; the C side
     * verifies again at the conversion boundary - no trust across modules). */
    {
        int min_ls[4] = {0, 0, 0, 0};
        if (av_image_fill_linesizes(min_ls, (enum AVPixelFormat)src->format, src->width) < 0) {
            return AVERROR(EINVAL);
        }
        for (i = 0; i < 4; i++) {
            int plane_h;
            int64_t need;
            if (src->data[i] == NULL) { continue; }
            if (src->linesize[i] < min_ls[i]) { return AVERROR(EINVAL); }
            plane_h = (i == 1 || i == 2) ? AV_CEIL_RSHIFT(src->height, d->log2_chroma_h) : src->height;
            need = (int64_t)src->linesize[i] * (plane_h > 1 ? (int64_t)plane_h - 1 : 0) + min_ls[i];
            if (src->buf[i] != NULL) {
                if ((int64_t)src->buf[i]->size < need) { return AVERROR(EINVAL); }
            } else if (src->buf[0] != NULL && src->data[0] != NULL) {
                int64_t off = (int64_t)(src->data[i] - src->buf[0]->data);
                if (off < 0 || off + need > (int64_t)src->buf[0]->size) { return AVERROR(EINVAL); }
            } else {
                return AVERROR(EINVAL); /* no refcounted backing to verify against */
            }
        }
    }
    /* v4: aggregate byte budget BEFORE the destination allocation - a 16k
     * frame otherwise allocates ~400 MiB on a single call. */
    /* v4.4 (r6 g5): bt2020 CONSTANT-LUMINANCE cannot be reduced with the
     * NCL matrix - refuse at the C boundary too, not only via the Swift
     * caller. */
    if (src->colorspace == AVCOL_SPC_BT2020_CL) { return AVERROR(EINVAL); }
    /* v4.4 repair (r6 g5): only the matrices actually mapped below
     * (601/709/2020 NCL) or UNSPECIFIED (documented 709 default) may proceed;
     * any other KNOWN matrix is refused at the boundary, never silently
     * converted through 709. */
    if (src->colorspace != AVCOL_SPC_UNSPECIFIED &&
        src->colorspace != AVCOL_SPC_BT709 &&
        src->colorspace != AVCOL_SPC_BT470BG &&
        src->colorspace != AVCOL_SPC_SMPTE170M &&
        src->colorspace != AVCOL_SPC_BT2020_NCL) { return AVERROR(EINVAL); }
    {
        /* v4.4 repair (r6 g6): the budget is checked against the EXACT
         * allocation model - the floor-chroma estimate was not a bound. */
        int64_t est = gorav_l3_yuv420p_alloc_estimate(src->width, src->height);
        if (est < 0) { return AVERROR(EINVAL); }
        if (est > GORAV_L3_MAX_CONVERT_BYTES) { return AVERROR(ENOSPC); }
    }
    src_range = src->color_range == AVCOL_RANGE_JPEG;
    if (pc->ctx == NULL || pc->src_fmt != src->format ||
        pc->src_w != src->width || pc->src_h != src->height ||
        pc->src_range != src_range || pc->src_csp != (int)src->colorspace) {
        if (pc->ctx != NULL) { sws_freeContext(pc->ctx); pc->ctx = NULL; }
        pc->ctx = sws_getContext(src->width, src->height, (enum AVPixelFormat)src->format,
                                 src->width, src->height, AV_PIX_FMT_YUV420P,
                                 SWS_BILINEAR | SWS_ACCURATE_RND | SWS_BITEXACT,
                                 NULL, NULL, NULL);
        if (pc->ctx == NULL) { return AVERROR(EINVAL); }
        /* v4.3 (architect r5): coefficient set by the SOURCE's ACTUAL matrix
         * - 601 sources (bt470bg/smpte170m) get 601, bt709 gets 709,
         * bt2020 NCL gets 2020 NCL, unspecified gets 709 and the Swift side
         * says so in provenance. bt2020-CL never reaches here (refused by
         * the caller - the NCL matrix would be a WRONG transform for CL).
         * v4 forced 709 onto every source; v4.2 split only 709/2020 and let
         * 601 sources convert through the wrong matrix. */
        int coeffSet = SWS_CS_ITU709;
        if (src->colorspace == AVCOL_SPC_BT470BG || src->colorspace == AVCOL_SPC_SMPTE170M) {
            coeffSet = SWS_CS_ITU601;
        } else if (src->colorspace == AVCOL_SPC_BT2020_NCL) {
            coeffSet = SWS_CS_BT2020; /* actual constant name in n8.0.1 swscale.h (first compile caught SWS_CS_ITU2020 undeclared) */
        } else if (src->colorspace == AVCOL_SPC_UNSPECIFIED) {
            /* arch-196x item 2 (v4.4 amendment, mpv parity): untagged ->
             * bt709 at width>=1280 or height>576, else bt601 - the guess the
             * default mpv path makes, and what the Swift provenance names.
             * (For this yuv->yuv bit-depth reduction the coefficient set is
             * pixel-neutral; the guess governs the downstream RGB stage.) */
            coeffSet = (src->width >= 1280 || src->height > 576) ? SWS_CS_ITU709 : SWS_CS_ITU601;
        }
        coeffs = sws_getCoefficients(coeffSet);
        ret = sws_setColorspaceDetails(pc->ctx, coeffs, src_range, coeffs, 0, 0, 1 << 16, 1 << 16);
        if (ret < 0) { sws_freeContext(pc->ctx); pc->ctx = NULL; return ret; }
        pc->src_fmt = (enum AVPixelFormat)src->format;
        pc->src_w = src->width;
        pc->src_h = src->height;
        pc->src_range = src_range;
        pc->src_csp = (int)src->colorspace;
    }
    av_frame_unref(dst);
    dst->format = AV_PIX_FMT_YUV420P;
    dst->width = src->width;
    dst->height = src->height;
    ret = av_frame_get_buffer(dst, 32);
    if (ret < 0) { return ret; }
    ret = sws_scale(pc->ctx, (const uint8_t *const *)src->data, src->linesize,
                    0, src->height, dst->data, dst->linesize);
    if (ret != src->height) { av_frame_unref(dst); return AVERROR_EXTERNAL; }
    ret = av_frame_copy_props(dst, src);
    if (ret < 0) { av_frame_unref(dst); return ret; }
    /* v4.3 (architect r5): the derived frame is a bit-depth reduction of
     * the source, NOT an SDR render - no EOTF mapping ran. Transfer,
     * primaries and matrix tags stay the SOURCE's (via copy_props): the
     * encoded values keep the source signal. But the RANGE was actually
     * converted (sws dst_range = limited above), so the copy is TAGGED
     * limited - inheriting a source FULL tag would be false provenance.
     * v4 stripped all tags and forced bt709 (mislabeled render); v4.2 kept
     * tags including a possibly-full range (false provenance). Both fixed. */
    dst->color_range = AVCOL_RANGE_MPEG;
    return 0;
}

/* --- Audio conversion: any admitted audio frame -> packed s16le stereo --- */

#define GORAV_L3_MAX_OUT_SAMPLES 262144 /* 1 MiB s16le stereo bound, pre-allocation */

struct GorAVL3Swr {
    struct SwrContext *ctx;
    enum AVSampleFormat in_fmt;
    int in_rate;
    AVChannelLayout in_layout;
    int out_rate;
    int reinits; /* reinit drops buffered delay: counted, never silent */
};

static inline struct GorAVL3Swr *gorav_l3_swr_open(void) {
    struct GorAVL3Swr *s = (struct GorAVL3Swr *)calloc(1, sizeof(struct GorAVL3Swr));
    return s;
}

static inline void gorav_l3_swr_close(struct GorAVL3Swr **s) {
    if (s == NULL || *s == NULL) { return; }
    if ((*s)->ctx != NULL) { swr_free(&(*s)->ctx); }
    av_channel_layout_uninit(&(*s)->in_layout);
    free(*s);
    *s = NULL;
}

/* Converts one decoded audio frame to packed s16le stereo at out_rate.
 * On success *out_data is an av_malloc'd buffer of *out_samples * 4 bytes,
 * ownership to the caller (free with gorav_l3_av_freep).
 * Returns 0, or negative AVERROR. Re-inits on format/rate/layout change. */
static inline int gorav_l3_swr_convert(struct GorAVL3Swr *s, const AVFrame *src,
                                       int out_rate, uint8_t **out_data, int *out_samples) {
    int ret;
    AVChannelLayout out_layout;
    int out_count;
    uint8_t *outp[1];
    uint8_t *tail = NULL;
    int tail_samples = 0;
    int64_t need64;
    if (s == NULL || src == NULL || out_data == NULL || out_samples == NULL) { return AVERROR(EINVAL); }
    *out_data = NULL;
    *out_samples = 0;
    if (src->nb_samples <= 0) { return 0; }
    if (src->sample_rate <= 0 || src->ch_layout.nb_channels <= 0 || out_rate <= 0) { return AVERROR(EINVAL); }
    if (s->ctx == NULL || s->in_fmt != src->format || s->in_rate != src->sample_rate ||
        s->out_rate != out_rate || av_channel_layout_compare(&s->in_layout, &src->ch_layout) != 0) {
        /* v4 (architect): a reinit used to DROP the old context's buffered
         * delay silently. Drain the old configuration's tail first and
         * prepend it to this call's output, so sample totals stay conserved
         * across the reinit. reinits counts ONLY actual re-inits (an old
         * context existed), never the first init, and is reported. */
        if (s->ctx != NULL) {
            int64_t old_delay = swr_get_delay(s->ctx, s->in_rate);
            if (old_delay > 0) {
                int64_t t64 = av_rescale_rnd(old_delay, s->out_rate, s->in_rate, AV_ROUND_UP);
                if (t64 > 0 && t64 <= GORAV_L3_MAX_OUT_SAMPLES) {
                    tail = (uint8_t *)av_malloc((size_t)t64 * 4);
                    if (tail != NULL) {
                        uint8_t *tp[1];
                        int t;
                        tp[0] = tail;
                        t = swr_convert(s->ctx, tp, (int)t64, NULL, 0);
                        if (t > 0) { tail_samples = t; } else { av_freep(&tail); }
                    }
                }
            }
            s->reinits++;
            swr_free(&s->ctx); s->ctx = NULL;
        }
        av_channel_layout_uninit(&s->in_layout);
        av_channel_layout_default(&out_layout, 2); /* stereo, matches the sink contract */
        ret = swr_alloc_set_opts2(&s->ctx, &out_layout, AV_SAMPLE_FMT_S16, out_rate,
                                  &src->ch_layout, (enum AVSampleFormat)src->format,
                                  src->sample_rate, 0, NULL);
        av_channel_layout_uninit(&out_layout);
        if (ret < 0 || s->ctx == NULL) { av_freep(&tail); return ret < 0 ? ret : AVERROR(EINVAL); }
        ret = swr_init(s->ctx);
        if (ret < 0) { av_freep(&tail); swr_free(&s->ctx); return ret; }
        s->in_fmt = (enum AVSampleFormat)src->format;
        s->in_rate = src->sample_rate;
        s->out_rate = out_rate;
        ret = av_channel_layout_copy(&s->in_layout, &src->ch_layout);
        if (ret < 0) { av_freep(&tail); swr_free(&s->ctx); return ret; }
    }
    /* v4: the rescale is bounded in int64 BEFORE the int conversion - the
     * old code truncated a >INT32_MAX rescale through (int) and only then
     * compared against the cap. delay+nb_samples is an int64 sum. */
    need64 = av_rescale_rnd(swr_get_delay(s->ctx, src->sample_rate) + (int64_t)src->nb_samples,
                            out_rate, src->sample_rate, AV_ROUND_UP);
    if (need64 < 0) { av_freep(&tail); return AVERROR(EINVAL); }
    if (need64 + tail_samples > GORAV_L3_MAX_OUT_SAMPLES) { av_freep(&tail); return AVERROR(ENOSPC); }
    out_count = (int)need64;
    if (out_count == 0 && tail_samples == 0) { return 0; }
    *out_data = (uint8_t *)av_malloc(((size_t)out_count + (size_t)tail_samples) * 4);
    if (*out_data == NULL) { av_freep(&tail); return AVERROR(ENOMEM); }
    if (tail_samples > 0) {
        memcpy(*out_data, tail, (size_t)tail_samples * 4);
        av_freep(&tail);
    }
    outp[0] = *out_data + (size_t)tail_samples * 4;
    ret = out_count > 0
        ? swr_convert(s->ctx, outp, out_count,
                      (const uint8_t **)src->extended_data, src->nb_samples)
        : 0;
    if (ret < 0) { av_freep(out_data); return ret; }
    *out_samples = tail_samples + ret;
    if (*out_samples == 0) { av_freep(out_data); }
    return 0;
}

/* v4: actual re-init count (first init excluded) for the run receipt. */
static inline int gorav_l3_swr_reinits(const struct GorAVL3Swr *s) {
    return s != NULL ? s->reinits : 0;
}

/* Drains the resampler's delay buffer at EOS (blocker 4: tail samples are
 * real audio; losing them shortens duration and drifts the clock). */
static inline int gorav_l3_swr_drain(struct GorAVL3Swr *s, uint8_t **out_data, int *out_samples) {
    int out_count;
    uint8_t *outp[1];
    int ret;
    if (s == NULL || out_data == NULL || out_samples == NULL) { return AVERROR(EINVAL); }
    *out_data = NULL;
    *out_samples = 0;
    if (s->ctx == NULL || s->out_rate <= 0) { return 0; }
    /* v4: int64 bound BEFORE the int conversion (same truncation fix). */
    {
        int64_t need64 = av_rescale_rnd(swr_get_delay(s->ctx, s->in_rate), s->out_rate, s->in_rate, AV_ROUND_UP);
        if (need64 < 0) { return AVERROR(EINVAL); }
        if (need64 > GORAV_L3_MAX_OUT_SAMPLES) { return AVERROR(ENOSPC); }
        out_count = (int)need64;
    }
    if (out_count == 0) { return 0; }
    *out_data = (uint8_t *)av_malloc((size_t)out_count * 4);
    if (*out_data == NULL) { return AVERROR(ENOMEM); }
    outp[0] = *out_data;
    ret = swr_convert(s->ctx, outp, out_count, NULL, 0);
    if (ret < 0) { av_freep(out_data); return ret; }
    *out_samples = ret;
    if (ret == 0) { av_freep(out_data); }
    return 0;
}

/* HDR signal descriptor values (blocker 1): mastering display + content
 * light level side data, presence distinguished from zero values. Color
 * enums (primaries/trc/space/range) live on AVFrame fields and are read
 * directly from Swift with the av_color_*_name() public API. */
struct GorAVL3HDRValues {
    int has_mastering;           /* side data present */
    int mastering_has_lum;       /* AVMasteringDisplayMetadata.has_luminance */
    int mastering_has_prim;      /* has_primaries */
    int max_lum_num, max_lum_den;
    int min_lum_num, min_lum_den;
    /* v4 (L5): display primaries + white point as rational xy pairs, valid
     * only when mastering_has_prim != 0. GBR order, matching
     * AVMasteringDisplayMetadata.display_primaries. */
    int prim_num[6], prim_den[6];  /* G(x,y), B(x,y), R(x,y) */
    int wp_num[2], wp_den[2];      /* white point x, y */
    int has_cll;                 /* side data present */
    unsigned max_cll, max_fall;
    /* v4 (L5): AVFrame.chroma_location verbatim (AVChromaLocation as int;
     * 0 = unspecified). Typed mapping is the Swift side's, no assumption here. */
    int chroma_location;
};
static inline struct GorAVL3HDRValues gorav_l3_hdr_values(const AVFrame *f) {
    struct GorAVL3HDRValues v;
    AVFrameSideData *sd;
    memset(&v, 0, sizeof(v));
    if (f == NULL) { return v; }
    sd = av_frame_get_side_data(f, AV_FRAME_DATA_MASTERING_DISPLAY_METADATA);
    if (sd != NULL && sd->data != NULL && sd->size >= sizeof(AVMasteringDisplayMetadata)) {
        const AVMasteringDisplayMetadata *md = (const AVMasteringDisplayMetadata *)sd->data;
        int i, j;
        v.has_mastering = 1;
        v.mastering_has_lum = md->has_luminance;
        v.mastering_has_prim = md->has_primaries;
        v.max_lum_num = md->max_luminance.num;
        v.max_lum_den = md->max_luminance.den;
        v.min_lum_num = md->min_luminance.num;
        v.min_lum_den = md->min_luminance.den;
        if (md->has_primaries) {
            for (i = 0; i < 3; i++) {
                for (j = 0; j < 2; j++) {
                    v.prim_num[i*2+j] = md->display_primaries[i][j].num;
                    v.prim_den[i*2+j] = md->display_primaries[i][j].den;
                }
            }
            for (j = 0; j < 2; j++) {
                v.wp_num[j] = md->white_point[j].num;
                v.wp_den[j] = md->white_point[j].den;
            }
        }
    }
    v.chroma_location = (int)f->chroma_location;
    sd = av_frame_get_side_data(f, AV_FRAME_DATA_CONTENT_LIGHT_LEVEL);
    if (sd != NULL && sd->data != NULL && sd->size >= sizeof(AVContentLightMetadata)) {
        const AVContentLightMetadata *cl = (const AVContentLightMetadata *)sd->data;
        v.has_cll = 1;
        v.max_cll = cl->MaxCLL;
        v.max_fall = cl->MaxFALL;
    }
    return v;
}

static inline void gorav_l3_av_freep(void *p) {
    void **pp = (void **)p;
    av_freep(pp);
}

/* v4.2: full swr state reset for seek - drops converter-internal delay and
 * any source-format leftovers so post-seek conversion starts clean. */
static inline int gorav_l3_swr_reset(SwrContext *swr) {
    return swr_init(swr);
}

/* v4.4 (r6 g3): the resampler's current delay in INPUT samples at the given
 * input rate - the output-side timing correction the audio lane applies
 * when it computes an emitted chunk's first-sample time. Negative = error. */
static inline int64_t gorav_l3_swr_delay(const struct GorAVL3Swr *s, int64_t input_rate) {
    if (!s || !s->ctx) { return -1; }
    return swr_get_delay(s->ctx, input_rate);
}

/* =================== AUTHORED_R3 section begins ===================
 * R3 (arch-195b): remote open with transport options. AVDictionary is not
 * importable by Swift, so the dictionary is built, passed and freed entirely
 * on the C side; Swift only supplies the already-joined strings (or NULL).
 * Returns the avformat_open_input result code. */
static inline int gorav_r3_open_input(AVFormatContext **ctx, const char *url,
                                      const char *headers, const char *cookies) {
    AVDictionary *d = NULL;
    int rc;
    if (headers != NULL && headers[0] != '\0') { av_dict_set(&d, "headers", headers, 0); }
    if (cookies != NULL && cookies[0] != '\0') { av_dict_set(&d, "cookies", cookies, 0); }
    rc = avformat_open_input(ctx, url, NULL, d != NULL ? &d : NULL);
    av_dict_free(&d);
    return rc;
}

/* =================== AUTHORED_R10 section begins ===================
 * R10 (arch-195b): media inventory accessors. AVDictionary and the
 * AV_DISPOSITION_* macros are not Swift-importable, so stream/format/chapter
 * facts cross through these wrappers only. No mutation; reads only. */
static inline int gorav_r10_stream_count(const AVFormatContext *f) {
    return f != NULL ? (int)f->nb_streams : 0;
}
/* codec_type as int: 0 video, 1 audio, 2 data, 3 subtitle, -1 unknown/other. */
static inline int gorav_r10_stream_kind(const AVFormatContext *f, int idx) {
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return -1; }
    switch (f->streams[idx]->codecpar->codec_type) {
        case AVMEDIA_TYPE_VIDEO: return 0;
        case AVMEDIA_TYPE_AUDIO: return 1;
        case AVMEDIA_TYPE_DATA: return 2;
        case AVMEDIA_TYPE_SUBTITLE: return 3;
        default: return -1;
    }
}
static inline const char *gorav_r10_stream_codec_name(const AVFormatContext *f, int idx) {
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return NULL; }
    return avcodec_get_name(f->streams[idx]->codecpar->codec_id);
}
static inline int gorav_r10_stream_disposition(const AVFormatContext *f, int idx) {
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return 0; }
    return f->streams[idx]->disposition;
}
static inline int gorav_r10_disposition_default(void) { return AV_DISPOSITION_DEFAULT; }
static inline int gorav_r10_disposition_attached_pic(void) { return AV_DISPOSITION_ATTACHED_PIC; }
static inline int64_t gorav_r10_stream_duration_ts(const AVFormatContext *f, int idx) {
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return AV_NOPTS_VALUE; }
    return f->streams[idx]->duration;
}
static inline void gorav_r10_stream_timebase(const AVFormatContext *f, int idx, int *num, int *den) {
    if (num != NULL) { *num = 0; }
    if (den != NULL) { *den = 0; }
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return; }
    if (num != NULL) { *num = f->streams[idx]->time_base.num; }
    if (den != NULL) { *den = f->streams[idx]->time_base.den; }
}
static inline const char *gorav_r10_stream_meta(const AVFormatContext *f, int idx, const char *key) {
    const AVDictionaryEntry *e;
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams || key == NULL) { return NULL; }
    e = av_dict_get(f->streams[idx]->metadata, key, NULL, 0);
    return e != NULL ? e->value : NULL;
}
static inline const char *gorav_r10_format_meta(const AVFormatContext *f, const char *key) {
    const AVDictionaryEntry *e;
    if (f == NULL || key == NULL) { return NULL; }
    e = av_dict_get(f->metadata, key, NULL, 0);
    return e != NULL ? e->value : NULL;
}
static inline int64_t gorav_r10_duration_us(const AVFormatContext *f) {
    return f != NULL ? f->duration : AV_NOPTS_VALUE;
}
static inline int gorav_r10_chapter_count(const AVFormatContext *f) {
    return f != NULL ? (int)f->nb_chapters : 0;
}
static inline void gorav_r10_chapter_times(const AVFormatContext *f, int idx,
                                           int64_t *start, int64_t *end, int *num, int *den) {
    if (start != NULL) { *start = 0; }
    if (end != NULL) { *end = 0; }
    if (num != NULL) { *num = 0; }
    if (den != NULL) { *den = 1; }
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_chapters) { return; }
    if (start != NULL) { *start = f->chapters[idx]->start; }
    if (end != NULL) { *end = f->chapters[idx]->end; }
    if (num != NULL) { *num = f->chapters[idx]->time_base.num; }
    if (den != NULL) { *den = f->chapters[idx]->time_base.den; }
}
static inline const char *gorav_r10_chapter_title(const AVFormatContext *f, int idx) {
    const AVDictionaryEntry *e;
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_chapters) { return NULL; }
    e = av_dict_get(f->chapters[idx]->metadata, "title", NULL, 0);
    return e != NULL ? e->value : NULL;
}

#endif /* GORAV_CFFMPEG_SHIM_H */
