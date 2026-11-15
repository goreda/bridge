/* rt_avformat_adapter.h - PROPOSED avformat binding for rt_transport.
 *
 * STATUS: PROPOSED / BLOCKED_INPUT. This workspace has no FFmpeg dev
 * headers, so this binding cannot be compiled or verified here. It is a
 * pinned mapping of rt_transport onto avformat's URLProtocol contract,
 * recorded so the local integrator can wire it in the native build lane
 * without re-deriving semantics. Version pins that MUST be confirmed
 * against the integrator's avformat before acceptance:
 *   - URLProtocol struct layout (ffurl_* era vs avio_* era fields)
 *   - AVSEEK_SIZE / AVSEEK_FORCE whence bits (we mirror 0x10000)
 *   - AVIOInterruptCB semantics (nonzero return = abort)
 *   - AVERROR mapping of RTStatus codes
 * Nothing below invents server behavior; it only maps engine semantics.
 */
#ifndef RT_AVFORMAT_ADAPTER_H
#define RT_AVFORMAT_ADAPTER_H

#include "rt_transport.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Pinned mapping (proposed):
 *
 *   URLProtocol.url_open   -> rt_wire_posix_open (or integrator wire) +
 *                             rt_open; probe runs here, capabilities fixed
 *                             for the session.
 *   URLProtocol.url_read   -> rt_read; 0 at clean EOF, AVERROR(...) for
 *                             negative RTStatus (mapping table below).
 *   URLProtocol.url_seek   -> rt_seek64; supports SEEK_SET/CUR/END and
 *                             AVSEEK_SIZE (== RT_SEEK_SIZE). Seek on a
 *                             non-seekable resource returns
 *                             AVERROR(ENOSYS) from RT_ERR_NOT_SEEKABLE.
 *   URLProtocol.url_close  -> rt_close.
 *   URLProtocol.url_get_short_seek -> 0 (no short-seek fast path claimed;
 *                             every seek revalidates the entity).
 *   URLProtocol.url_get_file_handle -> -1 (no fd exposed; wire-owned).
 *   AVIOContext.interrupt_callback -> RTOptions.interrupt, checked before
 *                             every wire request, recv and retry sleep.
 *
 * Proposed AVERROR mapping (integrator confirms exact values per its
 * avutil version):
 *   RT_ERR_NETWORK/RT_ERR_RETRY_EXHAUSTED -> AVERROR(EIO)
 *   RT_ERR_PROTOCOL/RANGE_REFUSED         -> AVERROR_INVALIDDATA? NO -
 *       PROPOSED: AVERROR(ENOSYS) is wrong here; use AVERROR_PROTOCOL_
 *       FAILURE where present, else AVERROR(EIO) with log. PIN REQUIRED.
 *   RT_ERR_NOT_SEEKABLE                   -> AVERROR(ENOSYS) on seek,
 *                                            AVERROR(EPIPE)? NO. PIN.
 *   RT_ERR_ENTITY_CHANGED                 -> AVERROR_INVALIDDATA
 *   RT_ERR_CANCELLED                      -> AVERROR_EXIT
 *
 * Capability signaling (proposed): rt_get_capabilities snapshot is
 * exposed to the host as avpriv/options, NOT silently:
 *   - range_supported=false  -> AVIOContext.seekable = 0
 *   - range_supported=true   -> AVIOContext.seekable = AVIO_SEEKABLE_NORMAL
 *   - size_known             -> avio_size() answerable via RT_SEEK_SIZE
 *   - etag/last_modified     -> surfaced for cache validation by host
 * Backpressure contract (proposed): URLProtocol has no pull-based flow
 * control; the engine honors max_read_chunk as its recv window so a slow
 * relay never forces unbounded buffering. Integrator sets the window
 * from its cache policy at open time.
 */

/* Glue the integrator implements (sketch, compiles only with real avformat):
 *
 *   static int rt_avio_open(URLContext *h, const char *url, int flags) {
 *       RTOptions o = {0};
 *       o.interrupt = (RTInterruptFn)ff_check_interrupt;   // wraps avio cb
 *       o.interrupt_opaque = &h->interrupt_callback;
 *       o.max_read_chunk = RT_AVIO_WINDOW;                 // host policy
 *       RTWire wire; rt_wire_posix_open(&wire, 5000);      // or host wire
 *       return map_err(rt_open(&((RTPriv*)h->priv_data)->t, &wire, url, &o));
 *   }
 */

#ifdef __cplusplus
}
#endif
#endif
