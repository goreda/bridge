/* test_wire.c - posix-wire regression checks (review F1 + lower findings).
 * Needs the synthetic server on argv[1] for W2/W4; connect checks are local. */
#include "../src/rt_transport.h"
#include "../src/rt_wire_posix.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { \
    printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond); failures++; } \
    else printf("ok   %s\n", #cond); } while (0)

static double now_s(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int g_arm; static int g_calls;
static int interrupt_armed(void *o) { (void)o; return ++g_calls >= g_arm; }

int main(int argc, char **argv) {
    int port = argc > 1 ? atoi(argv[1]) : 8971;

    /* W1: 20000-char path exceeds RT_WIRE_MAX_REQUEST -> fail closed, no overflow */
    {
        RTWire w; RTWirePosixConfig cfg = { 1000, 1000, NULL, NULL };
        CHECK(rt_wire_posix_open_cfg(&w, &cfg) == 0);
        char url[20200];
        snprintf(url, sizeof url, "http://127.0.0.1:%d/", port);
        size_t base = strlen(url);
        memset(url + base, 'a', 20000); url[base + 20000] = 0;
        RTTransport *t = NULL;
        int rc = rt_open(&t, &w, url, NULL);
        CHECK(rc == RT_ERR_NETWORK && t == NULL);
        rt_wire_posix_free(&w);
    }
    /* W2: 4000-char path fits the dynamic buffer -> request is really sent
     * (server 404s the unknown path; engine reports typed PROTOCOL, no crash) */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        char url[4200];
        snprintf(url, sizeof url, "http://127.0.0.1:%d/", port);
        size_t base = strlen(url);
        memset(url + base, 'a', 4000); url[base + 4000] = 0;
        RTTransport *t = NULL;
        int rc = rt_open(&t, &w, url, NULL);
        CHECK(rc == RT_ERR_PROTOCOL && t == NULL);
        rt_wire_posix_free(&w);
    }
    /* W3: 3000-char extra header fits -> normal fetch works byte-exact */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        static char big[3001]; memset(big, 'H', 2990); big[2990] = 0;
        memcpy(big, "X-Pad: ", 7);
        const char *hdrs[1] = { big };
        RTOptions o = {0}; o.extra_headers = hdrs; o.n_extra_headers = 1;
        char url[64]; snprintf(url, sizeof url, "http://127.0.0.1:%d/norange", port);
        RTTransport *t = NULL;
        CHECK(rt_open(&t, &w, url, &o) == RT_OK);
        uint8_t b[8192]; size_t got = 0; ptrdiff_t n; int okd = 1;
        while ((n = rt_read(t, b, sizeof b)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (b[i] != (uint8_t)((got++) * 131u + 17u)) okd = 0;
        CHECK(n == 0 && okd && got == 150000);
        rt_close(t);
        rt_wire_posix_free(&w);
    }
    /* W4: bare-LF response lines parse correctly (read_line CR strip fix) */
    {
        RTWire w; rt_wire_posix_open(&w, 2000);
        char url[64]; snprintf(url, sizeof url, "http://127.0.0.1:%d/barelf", port);
        RTTransport *t = NULL;
        CHECK(rt_open(&t, &w, url, NULL) == RT_OK);
        RTCapabilities c; rt_get_capabilities(t, &c);
        CHECK(c.size_known && c.size == 50000);
        uint8_t b[8192]; size_t got = 0; ptrdiff_t n; int okd = 1;
        while ((n = rt_read(t, b, sizeof b)) > 0)
            for (ptrdiff_t i = 0; i < n; i++)
                if (b[i] != (uint8_t)((got++) * 131u + 17u)) okd = 0;
        CHECK(n == 0 && okd && got == 50000);
        rt_close(t);
        rt_wire_posix_free(&w);
    }
    /* W5: connect timeout bounds an unreachable host */
    {
        RTWire w; RTWirePosixConfig cfg = { 500, 300, NULL, NULL };
        rt_wire_posix_open_cfg(&w, &cfg);
        RTTransport *t = NULL;
        double t0 = now_s();
        int rc = rt_open(&t, &w, "http://10.255.255.1:8971/x", NULL);
        double dt = now_s() - t0;
        CHECK(rc == RT_ERR_NETWORK);
        CHECK(dt < 10.0);
        printf("info connect-timeout path took %.2fs\n", dt);
        rt_wire_posix_free(&w);
    }
    /* W6: wire-level interrupt aborts a stuck connect */
    {
        RTWire w; g_arm = 3; g_calls = 0;
        RTWirePosixConfig cfg = { 500, 30000, interrupt_armed, NULL };
        rt_wire_posix_open_cfg(&w, &cfg);
        RTTransport *t = NULL;
        double t0 = now_s();
        int rc = rt_open(&t, &w, "http://10.255.255.1:8971/x", NULL);
        double dt = now_s() - t0;
        CHECK(rc != 0 && t == NULL);
        CHECK(dt < 10.0);
        printf("info connect-interrupt path took %.2fs\n", dt);
        rt_wire_posix_free(&w);
    }

    printf(failures ? "WIRE RESULT: FAIL (%d)\n" : "WIRE RESULT: PASS\n", failures);
    return failures ? 1 : 0;
}
