/* rt_transport.c - engine for W-0286 / 195b-B7. See rt_transport.h. */
#include "rt_transport.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <errno.h>
#include <limits.h>
#include <strings.h> /* strncasecmp */

struct RTTransport {
    RTWire wire;
    char *url;
    RTOptions opts;
    /* capabilities */
    bool range_supported, size_known;
    uint64_t size;
    bool etag_known;      char etag[160];
    bool lm_known;        char last_modified[96];
    char server[128];
    /* stream state */
    bool exchange_open;   /* a body-bearing exchange is open at pos */
    bool body_known;      /* current body has a declared length */
    uint64_t body_left;   /* remaining bytes of current body, if known */
    int64_t pos;          /* logical stream position */
    /* stats */
    uint64_t bytes_read;
    unsigned requests, reconnects;
    unsigned reconnect_budget;
};

static const char *k_probe_range = "Range: bytes=0-0";

const char *rt_strerror(int s) {
    switch (s) {
    case RT_OK: return "ok";
    case RT_ERR_NETWORK: return "network I/O failure";
    case RT_ERR_PROTOCOL: return "protocol violation";
    case RT_ERR_NOT_SEEKABLE: return "resource is not seekable (ranges refused)";
    case RT_ERR_RANGE_REFUSED: return "range resume refused by server";
    case RT_ERR_ENTITY_CHANGED: return "entity changed between ranges";
    case RT_ERR_CANCELLED: return "cancelled by interrupt callback";
    case RT_ERR_RETRY_EXHAUSTED: return "reconnect budget exhausted";
    case RT_ERR_BADARG: return "bad argument";
    default: return "unknown status";
    }
}
const char *rt_version_string(void) {
    return "rt_transport 0.1.0 (W-0286/195b-B7)";
}

/* strict decimal u64: rejects sign, junk, overflow */
static bool parse_u64(const char *s, uint64_t *out) {
    if (!s || !*s || *s == '-' || *s == '+') return false;
    char *ep = NULL; errno = 0;
    unsigned long long v = strtoull(s, &ep, 10);
    if (errno || !ep || *ep) return false;
    *out = (uint64_t)v; return true;
}

/* overflow-checked signed add */
static bool add_i64(int64_t a, int64_t b, int64_t *out) {
    if ((b > 0 && a > INT64_MAX - b) || (b < 0 && a < INT64_MIN - b)) return false;
    *out = a + b; return true;
}

static void default_sleep(void *opaque, unsigned ms) {
    (void)opaque;
    struct timespec ts = { (time_t)(ms / 1000), (long)(ms % 1000) * 1000000L };
    nanosleep(&ts, NULL);
}

static int interrupted(RTTransport *t) {
    if (t->opts.interrupt && t->opts.interrupt(t->opts.interrupt_opaque))
        return RT_ERR_CANCELLED;
    return RT_OK;
}
static void sleep_ms(RTTransport *t, unsigned ms) {
    if (t->opts.sleep_ms) t->opts.sleep_ms(t->opts.sleep_opaque, ms);
    else default_sleep(NULL, ms);
}

static const char *find_header(const RTWireResponse *r, const char *name) {
    for (size_t i = 0; i < r->n_headers; i++)
        if (strncasecmp(r->headers[i].name, name, 64) == 0)
            return r->headers[i].value;
    return NULL;
}

/* Parse "bytes START-END/TOTAL" (TOTAL may be *). */
static bool parse_content_range(const char *v, uint64_t *start, uint64_t *end,
                                uint64_t *total, bool *total_known) {
    unsigned long long s, e; char tot[32];
    if (!v) return false;
    if (strncasecmp(v, "bytes ", 6) != 0) return false;
    if (sscanf(v + 6, "%llu-%llu/%31s", &s, &e, tot) != 3) return false;
    *start = s; *end = e;
    if (strcmp(tot, "*") == 0) { *total_known = false; *total = 0; }
    else {
        if (!parse_u64(tot, total)) return false;
        *total_known = true;
    }
    /* end == UINT64_MAX would wrap body_left = end-start+1 to 0 (false clean
     * EOF); it also cannot be a valid index into any addressable resource. */
    if (e == UINT64_MAX) return false;
    return e >= s;
}

static void copy_hdr(char *dst, size_t cap, const char *v) {
    if (!v) { dst[0] = 0; return; }
    snprintf(dst, cap, "%s", v);
}

/* Build request header list: caller extras + ours (Range, If-Range). */
static int do_request(RTTransport *t, const char *range_hdr, RTWireResponse *resp) {
    const char *hdrs[16]; size_t n = 0;
    char ifrange[320];
    for (size_t i = 0; i < t->opts.n_extra_headers && n < 13; i++)
        hdrs[n++] = t->opts.extra_headers[i];
    if (range_hdr) hdrs[n++] = range_hdr;
    if (range_hdr && t->etag_known) {
        snprintf(ifrange, sizeof ifrange, "If-Range: %s", t->etag);
        hdrs[n++] = ifrange;
    } else if (range_hdr && t->lm_known) {
        snprintf(ifrange, sizeof ifrange, "If-Range: %s", t->last_modified);
        hdrs[n++] = ifrange;
    }
    int rc = t->wire.request(t->wire.ctx, "GET", t->url, hdrs, n, resp);
    if (rc == 0) t->requests++;
    return rc;
}

static void capture_meta(RTTransport *t, const RTWireResponse *r) {
    const char *v;
    if ((v = find_header(r, "ETag")))        { t->etag_known = true; copy_hdr(t->etag, sizeof t->etag, v); }
    if ((v = find_header(r, "Last-Modified"))){ t->lm_known = true; copy_hdr(t->last_modified, sizeof t->last_modified, v); }
    if ((v = find_header(r, "Server")))       copy_hdr(t->server, sizeof t->server, v);
}

/* Validate a resume response for stream position pos. */
static int validate_resume(RTTransport *t, const RTWireResponse *r, uint64_t pos) {
    if (r->status == 200) {
        /* Server ignored Range/If-Range: entity changed, or ranges dropped. */
        const char *et = find_header(r, "ETag");
        if (t->etag_known && et && strcmp(et, t->etag) != 0) return RT_ERR_ENTITY_CHANGED;
        return RT_ERR_RANGE_REFUSED;
    }
    if (r->status != 206) return RT_ERR_PROTOCOL;
    uint64_t s, e, tot; bool tot_known;
    if (!parse_content_range(find_header(r, "Content-Range"), &s, &e, &tot, &tot_known))
        return RT_ERR_PROTOCOL;
    if (s != pos) return RT_ERR_PROTOCOL;
    if (tot_known && e >= tot) return RT_ERR_PROTOCOL; /* end past last valid index */
    if (tot_known && t->size_known && tot != t->size) return RT_ERR_ENTITY_CHANGED;
    const char *et = find_header(r, "ETag");
    if (t->etag_known && et && strcmp(et, t->etag) != 0) return RT_ERR_ENTITY_CHANGED;
    return RT_OK;
}

/* Open a body-bearing exchange at position pos (pos==size allowed: empty read). */
static int open_stream(RTTransport *t, uint64_t pos) {
    char range[64];
    const char *rh = NULL;
    if (t->range_supported) {
        snprintf(range, sizeof range, "Range: bytes=%llu-", (unsigned long long)pos);
        rh = range;
    } else if (pos > 0) {
        return RT_ERR_RANGE_REFUSED; /* cannot resume a non-seekable stream */
    }
    RTWireResponse resp;
    int rc = interrupted(t); if (rc) return rc;
    rc = do_request(t, rh, &resp);
    if (rc) return RT_ERR_NETWORK;
    if (!t->range_supported) {
        if (resp.status != 200) return RT_ERR_PROTOCOL;
        capture_meta(t, &resp);
        const char *cl = find_header(&resp, "Content-Length");
        if (cl) {
            if (!parse_u64(cl, &t->body_left)) return RT_ERR_PROTOCOL;
            t->body_known = true;
        } else { t->body_known = false; t->body_left = 0; }
    } else {
        rc = validate_resume(t, &resp, pos);
        if (rc) { t->wire.close(t->wire.ctx); return rc; }
        capture_meta(t, &resp);
        uint64_t s, e, tot; bool tk;
        parse_content_range(find_header(&resp, "Content-Range"), &s, &e, &tot, &tk);
        t->body_known = true; t->body_left = e - s + 1;
    }
    t->exchange_open = true;
    return RT_OK;
}

/* Reconnect after a drop: bounded retries with backoff, entity validated. */
static int reconnect(RTTransport *t) {
    for (unsigned k = 0; k < t->reconnect_budget; k++) {
        int rc = interrupted(t); if (rc) return rc;
        { /* bounded exponential backoff: 50ms * 2^k, shift capped (no UB
             at k>=32), sleep capped at 60s */
            unsigned shift = k < 11 ? k : 11;
            unsigned long ms = 50UL << shift;
            if (ms > 60000UL) ms = 60000UL;
            sleep_ms(t, (unsigned)ms);
        }
        t->wire.close(t->wire.ctx);
        t->exchange_open = false;
        rc = open_stream(t, (uint64_t)t->pos);
        if (rc == RT_OK) { t->reconnects++; return RT_OK; }
        if (rc == RT_ERR_ENTITY_CHANGED || rc == RT_ERR_CANCELLED) return rc;
        /* NETWORK / RANGE_REFUSED / PROTOCOL: keep retrying within budget */
    }
    return RT_ERR_RETRY_EXHAUSTED;
}

int rt_open(RTTransport **out, const RTWire *wire, const char *url,
            const RTOptions *opts) {
    if (!out || !wire || !wire->request || !wire->recv || !wire->close || !url)
        return RT_ERR_BADARG;
    RTTransport *t = calloc(1, sizeof *t);
    if (!t) return RT_ERR_NETWORK;
    t->wire = *wire;
    t->url = strdup(url);
    if (opts) {
        t->opts = *opts;
    }
    if (t->opts.max_read_chunk == 0) t->opts.max_read_chunk = 65536;
    t->reconnect_budget = t->opts.max_reconnects ? t->opts.max_reconnects : 5;

    /* probe */
    RTWireResponse resp;
    int rc = interrupted(t); if (rc) { rt_close(t); return rc; }
    rc = do_request(t, k_probe_range, &resp);
    if (rc) { int cr = interrupted(t); rt_close(t); return cr ? cr : RT_ERR_NETWORK; }
    if (resp.status == 206) {
        uint64_t s, e, tot; bool tk;
        if (!parse_content_range(find_header(&resp, "Content-Range"), &s, &e, &tot, &tk)
            || s != 0 || e != 0) { rt_close(t); return RT_ERR_PROTOCOL; }
        t->range_supported = true;
        if (tk) { t->size_known = true; t->size = tot; }
        capture_meta(t, &resp);
        t->wire.close(t->wire.ctx); /* discard the 1 probe body byte */
    } else if (resp.status == 200) {
        t->range_supported = false;
        capture_meta(t, &resp);
        const char *cl = find_header(&resp, "Content-Length");
        if (cl) {
            if (!parse_u64(cl, &t->size)) { rt_close(t); return RT_ERR_PROTOCOL; }
            t->size_known = true;
        }
        /* keep this exchange: body starts at 0 */
        t->exchange_open = true;
        if (t->size_known) { t->body_known = true; t->body_left = t->size; }
    } else {
        rt_close(t);
        return RT_ERR_PROTOCOL;
    }
    t->pos = 0;
    *out = t;
    return RT_OK;
}

int rt_get_capabilities(const RTTransport *t, RTCapabilities *out) {
    if (!t || !out) return RT_ERR_BADARG;
    memset(out, 0, sizeof *out);
    out->range_supported = t->range_supported;
    out->size_known = t->size_known; out->size = t->size;
    out->etag_known = t->etag_known; copy_hdr(out->etag, sizeof out->etag, t->etag_known ? t->etag : NULL);
    out->last_modified_known = t->lm_known; copy_hdr(out->last_modified, sizeof out->last_modified, t->lm_known ? t->last_modified : NULL);
    copy_hdr(out->server, sizeof out->server, t->server);
    out->bytes_read = t->bytes_read;
    out->requests = t->requests; out->reconnects = t->reconnects;
    return RT_OK;
}

ptrdiff_t rt_read(RTTransport *t, uint8_t *buf, size_t len) {
    if (!t || !buf) return RT_ERR_BADARG;
    if (len == 0) return 0;
    if (len > t->opts.max_read_chunk) len = t->opts.max_read_chunk; /* backpressure window */
    for (;;) {
        int rc = interrupted(t); if (rc) return rc;
        if (!t->exchange_open) {
            if (t->size_known && (uint64_t)t->pos >= t->size) return 0;
            rc = open_stream(t, (uint64_t)t->pos);
            if (rc == RT_ERR_NETWORK) { /* transient: spend reconnect budget */
                rc = reconnect(t);
                if (rc) return rc;
            } else if (rc) return rc;
        }
        size_t want = len;
        if (t->body_known && want > t->body_left) want = (size_t)t->body_left;
        if (want == 0) { /* declared body done */
            t->wire.close(t->wire.ctx); t->exchange_open = false;
            return 0;
        }
        ptrdiff_t n = t->wire.recv(t->wire.ctx, buf, want);
        if (n > 0) {
            t->pos += n; t->bytes_read += (uint64_t)n;
            if (t->body_known) t->body_left -= (uint64_t)n;
            return n;
        }
        /* n == 0: wire reports framing-complete end of THIS response body
         * (Content-Length satisfied / chunked terminator / close-delimited
         * end). n < 0: hard failure mid-body. Both justify resume only when
         * the declared size says more bytes exist; an unknown-size body
         * ending is clean (HTTP gives no way to detect its mid-body drop:
         * recorded limitation). */
        bool premature = t->size_known && (uint64_t)t->pos < t->size;
        t->wire.close(t->wire.ctx); t->exchange_open = false;
        if (!premature) return 0;
        rc = reconnect(t);
        if (rc) return rc;
        /* loop: reopen and continue */
    }
}

int64_t rt_seek64(RTTransport *t, int64_t off, int whence) {
    if (!t) return RT_ERR_BADARG;
    if (whence == RT_SEEK_SIZE)
        return t->size_known ? (int64_t)t->size : RT_ERR_NOT_SEEKABLE;
    int64_t target;
    switch (whence) {
    case SEEK_SET: target = off; break;
    case SEEK_CUR:
        if (!add_i64(t->pos, off, &target)) return RT_ERR_BADARG;
        break;
    case SEEK_END:
        if (!t->size_known) return RT_ERR_NOT_SEEKABLE;
        if (t->size > (uint64_t)INT64_MAX) return RT_ERR_BADARG; /* unrepresentable */
        if (!add_i64((int64_t)t->size, off, &target)) return RT_ERR_BADARG;
        break;
    default: return RT_ERR_BADARG;
    }
    if (target < 0) return RT_ERR_BADARG;
    if (t->size_known && (uint64_t)target > t->size) return RT_ERR_BADARG;
    if (target == t->pos) return t->pos; /* no-op works even unseekable */
    if (!t->range_supported) return RT_ERR_NOT_SEEKABLE;
    t->wire.close(t->wire.ctx); t->exchange_open = false;
    t->pos = target;
    return t->pos;
}

int64_t rt_tell(const RTTransport *t) { return t ? t->pos : RT_ERR_BADARG; }

void rt_close(RTTransport *t) {
    if (!t) return;
    if (t->exchange_open) t->wire.close(t->wire.ctx);
    free(t->url);
    free(t);
}
