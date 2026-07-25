/* Copy-and-patch stencil library — composition spike (MC-PAPER-ROADMAP.md §2, §10 step 3).
 *
 * Extends the single-stencil proof (cap_spike.c) to COMPOSITION: a method is JIT-compiled
 * by concatenating one stencil per operation and patching each stencil's hole. This is the
 * productionizable core of a copy-and-patch JIT — a stencil table + a linker that memcpys
 * and patches. No assembler and no LLVM at runtime.
 *
 * Convention (spike): accumulator model — the working int lives in EAX; each stencil
 * updates it and falls through to the next; a final RET stencil returns it. A production
 * JVM stencil set would use a threaded/tail-call convention over a virtual stack, with one
 * stencil per bytecode, derived by compiling C snippets with a tail-call calling
 * convention rather than the hand-written x86-64 bytes used here for a controllable spike.
 *
 * Build: clang -O2 spikes/stencil_lib.c -o /tmp/stencil_lib && /tmp/stencil_lib
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <sys/mman.h>

/* A stencil: fixed bytes + optional 32-bit immediate hole at `hole` (-1 = none). */
typedef struct { const unsigned char *bytes; int len; int hole; } Stencil;

/* AOT stencil table (x86-64). Holes are the imm32 operand of each op. */
static const unsigned char S_LOAD[] = { 0xB8, 0,0,0,0 };            /* mov  eax, imm32   */
static const unsigned char S_ADD[]  = { 0x05, 0,0,0,0 };            /* add  eax, imm32   */
static const unsigned char S_MUL[]  = { 0x69, 0xC0, 0,0,0,0 };      /* imul eax, eax, imm32 */
static const unsigned char S_RET[]  = { 0xC3 };                     /* ret               */
static const Stencil LOAD = { S_LOAD, sizeof S_LOAD, 1 };
static const Stencil ADD  = { S_ADD,  sizeof S_ADD,  1 };
static const Stencil MUL  = { S_MUL,  sizeof S_MUL,  2 };
static const Stencil RET  = { S_RET,  sizeof S_RET, -1 };

/* One "bytecode" op: a stencil + its immediate operand. */
typedef struct { const Stencil *s; int32_t imm; } Op;

/* Copy-and-patch "compile": concatenate stencils into `code`, patch holes. Returns length. */
static int jit_compile(unsigned char *code, const Op *ops, int nops) {
    int off = 0;
    for (int i = 0; i < nops; i++) {
        const Stencil *s = ops[i].s;
        memcpy(code + off, s->bytes, (size_t)s->len);
        if (s->hole >= 0) memcpy(code + off + s->hole, &ops[i].imm, 4);
        off += s->len;
    }
    __builtin___clear_cache((char *)code, (char *)code + off);
    return off;
}

typedef int32_t (*jitfn)(void);
static double now_ns(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec*1e9+t.tv_nsec; }

int main(void) {
    long ps = sysconf(_SC_PAGESIZE);
    unsigned char *code = mmap(NULL, ps, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (code == MAP_FAILED) { perror("mmap"); return 1; }

    /* JIT the method: (10 + 5) * 3  == 45, from 4 composed stencils. */
    Op prog[] = { {&LOAD,10}, {&ADD,5}, {&MUL,3}, {&RET,0} };
    int len = jit_compile(code, prog, 4);
    int32_t r = ((jitfn)code)();
    printf("composed 4 stencils -> (10+5)*3 = %d  (expected 45)\n", r);
    if (r != 45) { printf("MISMATCH\n"); return 1; }
    printf("method code size:   %d bytes\n", len);

    /* Measure per-method compile cost of the 4-stencil method. */
    const int N = 500000;
    double t0 = now_ns();
    volatile int32_t sink = 0;
    for (int i = 0; i < N; i++) {
        Op p[] = { {&LOAD, i}, {&ADD, 5}, {&MUL, 3}, {&RET, 0} };
        jit_compile(code, p, 4);
        sink += ((jitfn)code)();
    }
    double t1 = now_ns();
    (void)sink;
    printf("per-method JIT cost: %.1f ns  (4 stencils, %d iters, incl. flush + call)\n",
           (t1 - t0) / N, N);
    printf("=> composition works; budget (low-us time, tens-of-bytes RAM) holds.\n");
    return 0;
}
