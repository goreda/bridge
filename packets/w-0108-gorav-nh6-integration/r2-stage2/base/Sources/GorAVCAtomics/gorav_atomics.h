/* L1 rework v4 (architect PART1 findings + v2-review f1 + full-review):
 * C11 acquire/release atomics for the single-producer/single-consumer
 * real-time paths. Header only, no translation unit, no new dependency.
 *
 * v4: the atomic CELL ITSELF is C-owned and C-typed. The _Atomic uint64_t
 * lives ENTIRELY on the C side (Swift cannot import _Atomic types, so the
 * cell crosses the boundary as an opaque void*): gorav_acell_create
 * allocates with malloc, initializes with atomic_init, and proves
 * lock-freedom for the exact object (compile-time static assertion on the
 * type class AND a runtime atomic_is_lock_free check - a NULL return is a
 * typed refusal, never a fallback to non-atomic storage). No Swift
 * variable storage is ever aliased by an atomic access, and the cell's
 * lifetime is explicit (create/destroy), not ARC-tied value semantics. */
#ifndef GORAV_ATOMICS_H
#define GORAV_ATOMICS_H
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>

/* Compile-time: 64-bit atomics must be lock-free on every target we
 * support (2 = always lock-free). */
#if defined(ATOMIC_LLONG_LOCK_FREE)
_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "gorav atomics require lock-free 64-bit atomics");
#endif

/* Opaque C-owned atomic cell. The pointed-to object IS an
 * _Atomic uint64_t allocated by malloc; the type never crosses into Swift. */
static inline void *gorav_acell_create(uint64_t initial) {
    _Atomic uint64_t *p = (_Atomic uint64_t *)malloc(sizeof(_Atomic uint64_t));
    if (!p) return NULL;
    atomic_init(p, initial);
    if (!atomic_is_lock_free(p)) { free(p); return NULL; }
    return (void *)p;
}
static inline void gorav_acell_destroy(void *p) { free(p); }

static inline uint64_t gorav_aload(const void *p) {
    return atomic_load_explicit((const _Atomic uint64_t *)p, memory_order_acquire);
}
static inline void gorav_astore(void *p, uint64_t v) {
    atomic_store_explicit((_Atomic uint64_t *)p, v, memory_order_release);
}
static inline uint64_t gorav_afetch_add(void *p, uint64_t v) {
    return atomic_fetch_add_explicit((_Atomic uint64_t *)p, v, memory_order_acq_rel);
}
static inline int gorav_acas(void *p, uint64_t *expected, uint64_t desired) {
    return atomic_compare_exchange_strong_explicit((_Atomic uint64_t *)p, expected, desired,
                                                   memory_order_acq_rel, memory_order_acquire);
}

/* LANE-0 / architect 80b constraint A: CALLBACK ADMISSION packed into one
 * 64-bit cell: bit 63 = RETIRED, bits 62..0 = active reader count.
 * A reader enters only while NOT retired (single CAS); after retire it
 * touches NO payload and renders silence. The owner retires FIRST, then
 * waits admitted readers to drain to zero. This is a LOCAL payload-
 * lifetime fence: it claims NOTHING about provider quiescence. The
 * tombstone stays addressable (the cell is caller-owned). */
#define GORAV_ADMIT_RETIRED (1ULL << 63)
static inline int gorav_admit_enter(void *p) {
    /* S2 ONE-CONSUMER: admit only when NOT retired AND readers == 0.
       A busy cell (a reader in flight) REFUSES: the render path must
       render silence, never a second concurrent consumer (architect full
       verdict S2: PCM ring has exactly ONE consumer). */
    _Atomic uint64_t *a = (_Atomic uint64_t *)p;
    uint64_t cur = atomic_load_explicit(a, memory_order_acquire);
    for (;;) {
        if (cur & GORAV_ADMIT_RETIRED) return 0;
        if (cur != 0) return 0;              /* busy => refuse (silence) */
        if (atomic_compare_exchange_weak_explicit(a, &cur, 1,
                memory_order_acq_rel, memory_order_acquire)) return 1;
    }
}
static inline void gorav_admit_exit(void *p) {
    atomic_fetch_sub_explicit((_Atomic uint64_t *)p, 1, memory_order_acq_rel);
}
/* Sets RETIRED exactly once; returns the number of readers still inside
 * (0 = fully drained). Idempotent-safe: a second retire returns the
 * current reader count, the bit stays set. */
static inline uint64_t gorav_admit_retire(void *p) {
    uint64_t cur = atomic_load_explicit((const _Atomic uint64_t *)p, memory_order_acquire);
    for (;;) {
        uint64_t want = cur | GORAV_ADMIT_RETIRED;
        if (atomic_compare_exchange_weak_explicit((_Atomic uint64_t *)p, &cur, want,
                                                  memory_order_acq_rel, memory_order_acquire))
            return want & ~GORAV_ADMIT_RETIRED;
    }
}
static inline uint64_t gorav_admit_readers(const void *p) {
    return atomic_load_explicit((const _Atomic uint64_t *)p, memory_order_acquire) & ~GORAV_ADMIT_RETIRED;
}
static inline int gorav_admit_is_retired(const void *p) {
    return (atomic_load_explicit((const _Atomic uint64_t *)p, memory_order_acquire) & GORAV_ADMIT_RETIRED) != 0;
}
#endif
