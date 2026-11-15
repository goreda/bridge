/* rt_transport.h - HTTP range transport provider core (relay/torrent class).
 * W-0286 / 195b-B7. Portable C11, no external dependencies.
 *
 * Sits above a caller-supplied wire backend (one HTTP exchange at a time)
 * and exposes avformat-shaped read/seek/interrupt semantics plus
 * capability reporting. The avformat binding itself is a pinned ABI in
 * rt_avformat_adapter.h (proposed; see RESULT-PACKET.md BLOCKED_INPUT).
 */
#ifndef RT_TRANSPORT_H
#define RT_TRANSPORT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/types.h> /* ptrdiff_t on strict C11 targets */

#ifdef __cplusplus
extern "C" {
#endif

#define RT_VERSION_MAJOR 0
#define RT_VERSION_MINOR 1
#define RT_VERSION_PATCH 0

/* whence extension mirroring avformat AVSEEK_SIZE: query size without seeking */
#define RT_SEEK_SIZE 0x10000

/* typed status codes; negative = error */
typedef enum RTStatus {
    RT_OK                   =  0,
    RT_ERR_NETWORK          = -1, /* wire-level I/O failure */
    RT_ERR_PROTOCOL         = -2, /* malformed HTTP / contract violation */
    RT_ERR_NOT_SEEKABLE     = -3, /* seek requested, ranges not supported */
    RT_ERR_RANGE_REFUSED    = -4, /* server stopped honoring ranges on resume */
    RT_ERR_ENTITY_CHANGED   = -5, /* ETag/Last-Modified/total changed under us */
    RT_ERR_CANCELLED        = -6, /* interrupt callback fired */
    RT_ERR_RETRY_EXHAUSTED  = -7, /* reconnect budget spent */
    RT_ERR_BADARG           = -8  /* bad API argument */
} RTStatus;

const char *rt_strerror(int status);
const char *rt_version_string(void);

#define RT_MAX_RESP_HEADERS 32
typedef struct RTWireResponse {
    int status; /* e.g. 200, 206, 416 */
    struct { char name[64]; char value[256]; } headers[RT_MAX_RESP_HEADERS];
    size_t n_headers;
} RTWireResponse;

/* Wire ABI: exactly one exchange in flight per RTWire instance.
 * request() opens an exchange and fills the parsed response head.
 * recv() reads response-body bytes (0 = end of THIS response body, <0 = wire error).
 * close() ends the exchange; request() implicitly closes any open exchange.
 * recv must never return more than len bytes; the engine uses len as its
 * backpressure window.
 */
typedef struct RTWire {
    void *ctx;
    int (*request)(void *ctx, const char *method, const char *url,
                   const char *const *req_headers, size_t n_req_headers,
                   RTWireResponse *resp);
    ptrdiff_t (*recv)(void *ctx, uint8_t *buf, size_t len);
    void (*close)(void *ctx);
} RTWire;

typedef int  (*RTInterruptFn)(void *opaque); /* !=0 means cancel, avformat AVIOInterruptCB shape */
typedef void (*RTSleepFn)(void *opaque, unsigned ms);

typedef struct RTOptions {
    size_t max_read_chunk;    /* backpressure window: max bytes per recv (0 = 65536) */
    unsigned max_reconnects;  /* resume attempts per drop (0 = 5) */
    RTInterruptFn interrupt; void *interrupt_opaque; /* NULL = never cancelled */
    RTSleepFn sleep_ms; void *sleep_opaque;          /* NULL = nanosleep */
    const char *const *extra_headers; size_t n_extra_headers; /* e.g. caller auth */
} RTOptions;

/* Capability + live-stats snapshot. */
typedef struct RTCapabilities {
    bool range_supported;       /* probe got 206 + valid Content-Range */
    bool size_known;
    uint64_t size;
    bool etag_known;
    char etag[160];
    bool last_modified_known;
    char last_modified[96];
    char server[128];           /* Server header, "" if absent */
    /* live counters */
    uint64_t bytes_read;
    unsigned requests;
    unsigned reconnects;
} RTCapabilities;

typedef struct RTTransport RTTransport;

/* Opens and probes the resource (GET + Range: bytes=0-0). Never streams
 * body past the probe. */
int  rt_open(RTTransport **out, const RTWire *wire, const char *url,
             const RTOptions *opts);
/* Snapshot of capabilities and counters. */
int  rt_get_capabilities(const RTTransport *t, RTCapabilities *out);
/* Stream read at the logical position. Returns bytes read (0 = clean EOF
 * at declared size) or a negative RTStatus. Reconnect/resume is internal. */
ptrdiff_t rt_read(RTTransport *t, uint8_t *buf, size_t len);
/* whence: SEEK_SET / SEEK_CUR / SEEK_END / RT_SEEK_SIZE. Returns new
 * logical position (or size) or negative RTStatus. */
int64_t rt_seek64(RTTransport *t, int64_t off, int whence);
int64_t rt_tell(const RTTransport *t);
void rt_close(RTTransport *t);

#ifdef __cplusplus
}
#endif
#endif /* RT_TRANSPORT_H */
