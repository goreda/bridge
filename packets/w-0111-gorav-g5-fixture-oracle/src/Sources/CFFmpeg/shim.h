/* AUTHORED_R2 replacement (2026-10-16, ZDYM provider/build lane).
 * NOT the pinned r1 member (pin 3114B/562aa5ad...); byte identity is not claimed.
 * Role per DECODER-ONLY-TARGET-WIRING-r1: avformat/avcodec/avutil/frame/pixdesc/imgutils/buffer/mem
 * imports, error constants, frame classification, interrupt callback bridge.
 * Provider lock (P1): FFmpeg 8.0.1 @ 894da5ca7d742e4429ffb2af534fcda0103ef593,
 * private-prefix headers only. No system/Homebrew FFmpeg. */
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
#include <stdbool.h>
#include <stdint.h>

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
#endif /* GORAV_CFFMPEG_SHIM_H */
