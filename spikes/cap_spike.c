/* Copy-and-patch JIT spike (MC-PAPER-ROADMAP.md §2, §10 step 2).
 *
 * Proves the mechanism and measures its cost: a per-bytecode "stencil" is a normal
 * function compiled AHEAD OF TIME (here `stencil_add`), whose body contains a
 * patchable immediate ("hole", the magic 0x11223344). At runtime we JIT a method by:
 *   1) memcpy the stencil's machine-code bytes into an executable buffer,
 *   2) patch the hole with the operand for this specific call site,
 *   3) call it.
 * No compiler, no allocator, no LLVM at runtime — just memcpy + a few stores. This is
 * the "cheap JIT that edits native code" the roadmap requires.
 *
 * Build: clang -O2 spikes/cap_spike.c -o /tmp/cap_spike && /tmp/cap_spike
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/mman.h>

/* The stencil: `x + HOLE`. Compiled AOT. 0x11223344 is the patchable immediate.
 * Marked noinline + used so the compiler keeps a standalone body with the immediate. */
__attribute__((noinline)) int32_t stencil_add(int32_t x) {
    return x + 0x11223344;
}
/* A marker function right after, so (char*)stencil_end - (char*)stencil_add bounds the
 * stencil's byte length without parsing the object file. */
__attribute__((noinline)) void stencil_end(void) { __asm__ __volatile__(""); }

typedef int32_t (*addfn)(int32_t);

static double now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

int main(void) {
    const unsigned char *src = (const unsigned char *)stencil_add;
    long len = (long)((const unsigned char *)stencil_end - src);
    if (len <= 0 || len > 4096) { printf("could not bound stencil (len=%ld)\n", len); return 1; }

    /* Find the patchable immediate 0x11223344 (little-endian 44 33 22 11) in the body. */
    long hole = -1;
    for (long i = 0; i + 4 <= len; i++) {
        if (src[i] == 0x44 && src[i+1] == 0x33 && src[i+2] == 0x22 && src[i+3] == 0x11) { hole = i; break; }
    }
    if (hole < 0) { printf("hole not found in stencil (len=%ld) — try -O0\n", len); return 1; }

    /* One code page for all JITted methods (RWX allowed on this kernel; keeps EXEC). */
    long ps = sysconf(_SC_PAGESIZE);
    unsigned char *code = mmap(NULL, ps, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (code == MAP_FAILED) { perror("mmap"); return 1; }

    /* JIT one method: add constant 1000. memcpy the stencil, patch the hole. */
    memcpy(code, src, (size_t)len);
    int32_t operand = 1000;
    memcpy(code + hole, &operand, 4);
    __builtin___clear_cache((char*)code, (char*)code + len);
    addfn f = (addfn)code;
    int32_t r = f(42);
    printf("JIT result: f(42) with patched +%d = %d  (expected %d)\n", operand, r, 42 + operand);
    if (r != 42 + operand) { printf("MISMATCH\n"); return 1; }

    /* Measure per-method JIT cost: memcpy + patch + icache flush, N times. */
    const int N = 1000000;
    double t0 = now_ns();
    volatile int32_t sink = 0;
    for (int i = 0; i < N; i++) {
        memcpy(code, src, (size_t)len);
        int32_t op = i;
        memcpy(code + hole, &op, 4);
        __builtin___clear_cache((char*)code, (char*)code + len);
        sink += ((addfn)code)(0);
    }
    double t1 = now_ns();
    (void)sink;

    printf("stencil size:        %ld bytes\n", len);
    printf("hole offset:         %ld\n", hole);
    printf("per-method JIT cost: %.1f ns  (%d iterations, incl. icache flush + one call)\n",
           (t1 - t0) / N, N);
    printf("code RAM per method: %ld bytes (one stencil copy)\n", len);
    return 0;
}
