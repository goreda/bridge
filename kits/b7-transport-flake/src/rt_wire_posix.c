#define _GNU_SOURCE
#include "rt_wire_posix.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <strings.h>
#include <unistd.h>
#include <errno.h>
#include <netdb.h>
#include <poll.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/time.h>

typedef struct {
    int fd;
    unsigned timeout_ms;
    unsigned connect_timeout_ms;
    RTInterruptFn interrupt; void *interrupt_opaque;
    /* body framing */
    int chunked;
    int64_t cl_left;      /* -1 = until close */
    uint64_t chunk_left;  /* remaining in current chunk */
    int chunk_tail;       /* expect CRLF after chunk */
    /* header read buffer */
    char hbuf[8192];
    size_t hlen, hpos;
} PWire;

static void p_close(void *v) {
    PWire *p = v;
    if (p && p->fd >= 0) { close(p->fd); p->fd = -1; }
}

static ssize_t read_some(PWire *p, char *buf, size_t len) {
    ssize_t n = recv(p->fd, buf, len, 0);
    return n; /* 0 close, <0 error/timeout */
}

/* Body read honoring bytes already buffered during header parsing. */
static ssize_t read_body(PWire *p, char *buf, size_t len) {
    if (p->hpos < p->hlen) {
        size_t avail = p->hlen - p->hpos;
        if (len > avail) len = avail;
        memcpy(buf, p->hbuf + p->hpos, len);
        p->hpos += len;
        return (ssize_t)len;
    }
    return read_some(p, buf, len);
}

/* read one header line (LF terminated; CR stripped only when present).
 * returns 0 ok, 1 overlong (rest of line consumed, content truncated),
 * -1 I/O error. Bare-LF lines keep their full content. */
static int read_line(PWire *p, char *out, size_t cap) {
    size_t n = 0;
    int over = 0;
    for (;;) {
        if (p->hpos < p->hlen) {
            char c = p->hbuf[p->hpos++];
            if (c == '\n') {
                if (n && out[n - 1] == '\r') n--;
                out[n] = 0;
                return over;
            }
            if (n + 1 < cap) out[n++] = c;
            else over = 1; /* keep consuming to stay in framing sync */
        } else {
            ssize_t r = read_some(p, p->hbuf, sizeof p->hbuf);
            if (r <= 0) return -1;
            p->hlen = (size_t)r; p->hpos = 0;
        }
    }
}

static int p_request(void *v, const char *method, const char *url,
                     const char *const *hdrs, size_t n_hdrs,
                     RTWireResponse *resp) {
    PWire *p = v;
    p_close(p);
    /* parse http://host[:port]/path */
    if (strncmp(url, "http://", 7) != 0) return -1;
    const char *hp = url + 7;
    const char *slash = strchr(hp, '/');
    char host[256] = {0}, port[8] = "80";
    const char *colon = slash ? memchr(hp, ':', (size_t)(slash - hp)) : strchr(hp, ':');
    if (colon) {
        snprintf(host, sizeof host, "%.*s", (int)(colon - hp), hp);
        const char *pe = slash ? slash : hp + strlen(hp);
        snprintf(port, sizeof port, "%.*s", (int)(pe - colon - 1), colon + 1);
    } else {
        snprintf(host, sizeof host, "%.*s", slash ? (int)(slash - hp) : (int)strlen(hp), hp);
    }
    const char *path = slash ? slash : "/";

    char portstr[16]; snprintf(portstr, sizeof portstr, "%s", port);
    struct addrinfo hints = {0}, *ai = NULL;
    hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, portstr, &hints, &ai) != 0 || !ai) return -1;
    int fd = -1;
    for (struct addrinfo *a = ai; a; a = a->ai_next) {
        fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0) continue;
        /* bounded connect: non-blocking + poll in 50ms slices so the
         * interrupt callback can fire mid-connect */
        int fl = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
        int cr = connect(fd, a->ai_addr, a->ai_addrlen);
        if (cr != 0 && errno == EINPROGRESS) {
            unsigned waited = 0; cr = -1;
            while (waited < p->connect_timeout_ms) {
                if (p->interrupt && p->interrupt(p->interrupt_opaque)) { cr = -2; break; }
                unsigned slice = p->connect_timeout_ms - waited;
                if (slice > 50) slice = 50;
                struct pollfd pfd = { fd, POLLOUT, 0 };
                int pr = poll(&pfd, 1, (int)slice);
                waited += slice;
                if (pr > 0) {
                    int so = 0; socklen_t sl = sizeof so;
                    getsockopt(fd, SOL_SOCKET, SO_ERROR, &so, &sl);
                    cr = so ? -1 : 0;
                    break;
                }
                if (pr < 0 && errno != EINTR) break;
            }
        }
        fcntl(fd, F_SETFL, fl); /* restore blocking */
        if (cr == 0) break;
        close(fd); fd = -1;
        if (cr == -2) break; /* interrupted: stop trying addresses */
    }
    freeaddrinfo(ai);
    if (fd < 0) return -1;
    struct timeval tv = { (time_t)(p->timeout_ms / 1000), (suseconds_t)(p->timeout_ms % 1000) * 1000 };
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
    p->fd = fd;

    /* build request dynamically; fail closed beyond RT_WIRE_MAX_REQUEST */
    size_t need = strlen(method) + strlen(path) + strlen(host) + 64;
    for (size_t i = 0; i < n_hdrs; i++) {
        size_t hl = strlen(hdrs[i]);
        if (hl > RT_WIRE_MAX_REQUEST) { p_close(p); return -1; }
        need += hl + 2;
        if (need > RT_WIRE_MAX_REQUEST) { p_close(p); return -1; }
    }
    char *req = malloc(need);
    if (!req) { p_close(p); return -1; }
    size_t off = 0;
    int w0 = snprintf(req, need, "%s %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n",
                      method, path, host);
    if (w0 < 0 || (size_t)w0 >= need) { free(req); p_close(p); return -1; }
    off = (size_t)w0;
    for (size_t i = 0; i < n_hdrs; i++) {
        int wn = snprintf(req + off, need - off, "%s\r\n", hdrs[i]);
        if (wn < 0 || (size_t)wn >= need - off) { free(req); p_close(p); return -1; }
        off += (size_t)wn;
    }
    int wf = snprintf(req + off, need - off, "\r\n");
    if (wf != 2) { free(req); p_close(p); return -1; }
    off += 2;
    size_t sent = 0;
    while (sent < off) {
        ssize_t w = send(fd, req + sent, off - sent, 0);
        if (w <= 0) { free(req); p_close(p); return -1; }
        sent += (size_t)w;
    }
    free(req);

    /* parse response head */
    p->hlen = p->hpos = 0;
    char line[512];
    if (read_line(p, line, sizeof line) != 0) { p_close(p); return -1; } /* overlong status = fail */
    int status = 0;
    if (sscanf(line, "HTTP/%*d.%*d %d", &status) != 1) { p_close(p); return -1; }
    resp->status = status; resp->n_headers = 0;
    for (;;) {
        int lr = read_line(p, line, sizeof line);
        if (lr < 0) { p_close(p); return -1; }
        if (line[0] == 0) break;
        if (lr == 1) continue; /* overlong header: skipped, framing preserved */
        if (resp->n_headers >= RT_MAX_RESP_HEADERS) continue;
        char *c = strchr(line, ':');
        if (!c) continue;
        *c = 0;
        char *val = c + 1; while (*val == ' ') val++;
        snprintf(resp->headers[resp->n_headers].name, 64, "%.63s", line);
        snprintf(resp->headers[resp->n_headers].value, 256, "%.255s", val);
        resp->n_headers++;
    }
    /* framing */
    p->chunked = 0; p->cl_left = -1; p->chunk_left = 0; p->chunk_tail = 0;
    for (size_t i = 0; i < resp->n_headers; i++) {
        if (strncasecmp(resp->headers[i].name, "Transfer-Encoding", 64) == 0 &&
            strcasestr(resp->headers[i].value, "chunked")) p->chunked = 1;
        if (strncasecmp(resp->headers[i].name, "Content-Length", 64) == 0)
            p->cl_left = (int64_t)strtoll(resp->headers[i].value, NULL, 10);
    }
    if (status == 204 || status == 304 || (status >= 100 && status < 200)) p->cl_left = 0;
    return 0;
}

static ptrdiff_t p_recv(void *v, uint8_t *buf, size_t len) {
    PWire *p = v;
    if (p->fd < 0) return -1;
    if (p->chunked) {
        if (p->chunk_tail) { /* consume CRLF after data */
            char crlf[2]; size_t got = 0;
            while (got < 2) {
                ssize_t r = read_body(p, crlf + got, 2 - got);
                if (r <= 0) return -1;
                got += (size_t)r;
            }
            p->chunk_tail = 0;
        }
        while (p->chunk_left == 0) {
            char line[64];
            if (read_line(p, line, sizeof line) != 0) return -1;
            unsigned long cs = strtoul(line, NULL, 16);
            if (cs == 0) { p_close(p); return 0; } /* last chunk; trailers skipped */
            p->chunk_left = cs;
        }
        if (len > p->chunk_left) len = (size_t)p->chunk_left;
        ssize_t n = read_body(p, (char *)buf, len);
        if (n < 0) return -1;
        if (n == 0) return -1; /* drop inside a chunk */
        p->chunk_left -= (uint64_t)n;
        if (p->chunk_left == 0) p->chunk_tail = 1;
        return n;
    }
    if (p->cl_left == 0) return 0;
    if (p->cl_left > 0 && len > (size_t)p->cl_left) len = (size_t)p->cl_left;
    ssize_t n = read_body(p, (char *)buf, len);
    if (n < 0) return -1;           /* timeout or error: engine decides retry */
    if (n == 0) {
        /* connection closed: clean only for close-delimited bodies */
        return p->cl_left > 0 ? -1 : 0;
    }
    if (p->cl_left > 0) p->cl_left -= n;
    return n;
}

int rt_wire_posix_open_cfg(RTWire *wire, const RTWirePosixConfig *cfg) {
    if (!wire) return -1;
    PWire *p = calloc(1, sizeof *p);
    if (!p) return -1;
    p->fd = -1;
    p->timeout_ms = cfg && cfg->recv_timeout_ms ? cfg->recv_timeout_ms : 5000;
    p->connect_timeout_ms = cfg && cfg->connect_timeout_ms ? cfg->connect_timeout_ms : 5000;
    if (cfg) { p->interrupt = cfg->interrupt; p->interrupt_opaque = cfg->interrupt_opaque; }
    wire->ctx = p;
    wire->request = p_request;
    wire->recv = p_recv;
    wire->close = p_close;
    return 0;
}

int rt_wire_posix_open(RTWire *wire, unsigned recv_timeout_ms) {
    RTWirePosixConfig cfg = { recv_timeout_ms, 0, NULL, NULL };
    return rt_wire_posix_open_cfg(wire, &cfg);
}

void rt_wire_posix_free(RTWire *wire) {
    if (!wire || !wire->ctx) return;
    p_close(wire->ctx);
    free(wire->ctx);
    wire->ctx = NULL;
}
