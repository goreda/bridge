/* rt_wire_posix.h - minimal blocking HTTP/1.1 wire backend (synthetic use).
 * http:// URLs only, Connection: close per exchange, chunked decode included.
 * Request line+headers are built dynamically (cap RT_WIRE_MAX_REQUEST);
 * oversized requests fail closed. Connect is bounded by a timeout and an
 * optional interrupt callback. Not a production HTTP stack (see
 * RESULT-PACKET.md limits). */
#ifndef RT_WIRE_POSIX_H
#define RT_WIRE_POSIX_H
#include "rt_transport.h"

/* hard cap on a serialized request (request line + all headers) */
#define RT_WIRE_MAX_REQUEST 16384

typedef struct RTWirePosixConfig {
    unsigned recv_timeout_ms;    /* 0 = 5000 */
    unsigned connect_timeout_ms; /* 0 = 5000 */
    RTInterruptFn interrupt;     /* checked during connect; NULL = none */
    void *interrupt_opaque;
} RTWirePosixConfig;

int rt_wire_posix_open_cfg(RTWire *wire, const RTWirePosixConfig *cfg);
/* compat wrapper: recv timeout only, 5s connect, no wire-level interrupt */
int rt_wire_posix_open(RTWire *wire, unsigned recv_timeout_ms);

/* close any exchange and free the wire context. Callers own this. */
void rt_wire_posix_free(RTWire *wire);

#endif
