/* e2e_client.c - drives rt_transport over the posix wire against the
 * synthetic python server. Modes:
 *   e2e_client URL full <len>      read all, verify generator bytes
 *   e2e_client URL seek <len>      200 pseudo-random seeks + verifies
 *   e2e_client URL cancel <k>      interrupt after k bytes; expect CANCELLED
 * Prints one "E2E <mode> ..." verdict line and machine-readable stats. */
#include "../src/rt_transport.h"
#include "../src/rt_wire_posix.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t expect_byte(uint64_t i) { return (uint8_t)(i * 131u + 17u); }

static uint64_t g_seen; static uint64_t g_cancel_at;
static int interrupt_cb(void *o) { (void)o; return g_seen >= g_cancel_at; }

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage\n"); return 2; }
    const char *url = argv[1], *mode = argv[2];
    long arg = strtol(argv[3], NULL, 10);

    RTWire wire;
    RTOptions o = {0};
    if (strcmp(mode, "cancel") == 0) {
        o.interrupt = interrupt_cb; g_cancel_at = (uint64_t)arg;
        /* wire-level interrupt plumbed too (connect-time cancel path) */
        RTWirePosixConfig cfg = { 5000, 5000, interrupt_cb, NULL };
        if (rt_wire_posix_open_cfg(&wire, &cfg) != 0) { printf("E2E %s FAIL wire\n", mode); return 1; }
    } else {
        if (rt_wire_posix_open(&wire, 5000) != 0) { printf("E2E %s FAIL wire\n", mode); return 1; }
    }
    RTTransport *t = NULL;
    int rc = rt_open(&t, &wire, url, &o);
    if (rc != RT_OK) { printf("E2E %s FAIL open=%s\n", mode, rt_strerror(rc));
        rt_wire_posix_free(&wire); return 1; }
    RTCapabilities c; rt_get_capabilities(t, &c);
    printf("caps range=%d size_known=%d size=%llu etag=%s server=%s\n",
           c.range_supported, c.size_known, (unsigned long long)c.size,
           c.etag_known ? c.etag : "-", c.server);

    uint8_t buf[16384];
    int ok = 1;
    if (strcmp(mode, "full") == 0) {
        uint64_t got = 0; ptrdiff_t n;
        while ((n = rt_read(t, buf, sizeof buf)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (buf[i] != expect_byte(got++)) { ok = 0; break; }
        if (n < 0) { printf("E2E full FAIL read=%s\n", rt_strerror((int)n)); return 1; }
        ok = ok && got == (uint64_t)arg;
        printf("E2E full %s bytes=%llu\n", ok ? "PASS" : "FAIL", (unsigned long long)got);
    } else if (strcmp(mode, "seek") == 0) {
        uint32_t st = 12345;
        for (int k = 0; k < 200 && ok; k++) {
            st = st * 1664525u + 1013904223u;
            int64_t pos = (int64_t)(st % (uint32_t)arg);
            if (rt_seek64(t, pos, SEEK_SET) != pos) { ok = 0; break; }
            ptrdiff_t n = rt_read(t, buf, 997);
            int64_t want = arg - pos < 997 ? arg - pos : 997;
            if (n != want) { ok = 0; break; }
            for (ptrdiff_t i = 0; i < n; i++)
                if (buf[i] != expect_byte((uint64_t)pos + (uint64_t)i)) { ok = 0; break; }
        }
        printf("E2E seek %s\n", ok ? "PASS" : "FAIL");
    } else if (strcmp(mode, "cancel") == 0) {
        ptrdiff_t n; g_seen = 0;
        while ((n = rt_read(t, buf, 4096)) > 0) g_seen += (uint64_t)n;
        ok = (n == RT_ERR_CANCELLED);
        printf("E2E cancel %s bytes_before_cancel=%llu\n", ok ? "PASS" : "FAIL",
               (unsigned long long)g_seen);
    } else { printf("E2E unknown mode\n"); return 2; }

    rt_get_capabilities(t, &c);
    printf("stats requests=%u reconnects=%u bytes=%llu\n",
           c.requests, c.reconnects, (unsigned long long)c.bytes_read);
    rt_close(t);
    rt_wire_posix_free(&wire);
    return ok ? 0 : 1;
}
