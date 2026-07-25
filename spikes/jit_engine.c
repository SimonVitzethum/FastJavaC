/* Tier-1 copy-and-patch JIT engine — full-ish integer bytecode (roadmap §2).
 *
 * Compiles a JVM method's bytecode to native x86-64 at runtime by emitting one machine-
 * code stencil per bytecode (no assembler, no LLVM). Convention:
 *   - the JVM operand stack IS the machine stack (push/pop of 64-bit slots holding int32);
 *   - locals live in an int64 array passed in RDI (args placed by the caller);
 *   - RAX/RCX are scratch; RDI is preserved as the locals base.
 * A method is a leaf function `int32_t fn(int64_t *locals)`. The JVM verifier guarantees a
 * balanced operand stack, so at `ireturn` we pop the one result to EAX and `ret` (RSP is
 * back at the entry return address). Branches are resolved with a bytecode-pc -> native-
 * offset map and rel32 fixups.
 *
 * This is the standalone engine; runtime.c integrates the same logic. Supported opcodes:
 * iconst_m1..5, bipush, sipush, iload(_0..3), istore(_0..3), iadd, isub, imul, ineg, iinc,
 * dup, pop, goto, ifeq..ifle, if_icmpeq..le, ireturn.
 *
 * Build: clang -O2 spikes/jit_engine.c -o /tmp/jit_engine && /tmp/jit_engine
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

typedef int32_t (*jitfn)(int64_t *locals);

/* ---- tiny code emitter ---- */
static unsigned char CODE[8192];
static int LEN;
static void e1(unsigned char b){ CODE[LEN++] = b; }
static void eN(const void *p, int n){ memcpy(CODE + LEN, p, (size_t)n); LEN += n; }
static void e_i32(int32_t v){ eN(&v, 4); }

/* push/pop a local: FF 77 disp8  /  8F 47 disp8  (disp = 8*index) */
static void emit_push_local(int idx){ e1(0xFF); e1(0x77); e1((unsigned char)(8*idx)); }
static void emit_pop_local(int idx){ e1(0x8F); e1(0x47); e1((unsigned char)(8*idx)); }
static void emit_push_imm(int32_t v){ e1(0x68); e_i32(v); }          /* push imm32 */

/* branch fixups: patch a rel32 at CODE[off] to reach native offset of a bytecode pc */
typedef struct { int off; int target_pc; } Fixup;
static Fixup FIX[1024]; static int NFIX;
static int NOFF[8192]; /* bytecode pc -> native offset (-1 = unset) */

/* emit a conditional/uncond jump with a placeholder rel32; record a fixup to target_pc */
static void emit_jcc(unsigned char cc, int target_pc){ /* 0F 8x rel32 */
    e1(0x0F); e1(cc);
    FIX[NFIX].off = LEN; FIX[NFIX].target_pc = target_pc; NFIX++;
    e_i32(0);
}
static void emit_jmp(int target_pc){ /* E9 rel32 */
    e1(0xE9);
    FIX[NFIX].off = LEN; FIX[NFIX].target_pc = target_pc; NFIX++;
    e_i32(0);
}

static int16_t rd_s16(const uint8_t *b){ return (int16_t)((b[0]<<8)|b[1]); }

/* Compile bytecode -> native. Returns entry pointer, or NULL on unsupported opcode. */
static jitfn jit(const uint8_t *bc, int n) {
    LEN = 0; NFIX = 0;
    for (int i = 0; i <= n; i++) NOFF[i] = -1;

    int pc = 0;
    while (pc < n) {
        NOFF[pc] = LEN;
        uint8_t op = bc[pc];
        switch (op) {
            case 0x02: emit_push_imm(-1); pc++; break;                 /* iconst_m1 */
            case 0x03: case 0x04: case 0x05: case 0x06:
            case 0x07: case 0x08: emit_push_imm(op - 0x03); pc++; break;/* iconst_0..5 */
            case 0x10: emit_push_imm((int8_t)bc[pc+1]); pc += 2; break; /* bipush */
            case 0x11: emit_push_imm(rd_s16(bc+pc+1)); pc += 3; break;  /* sipush */
            case 0x15: emit_push_local(bc[pc+1]); pc += 2; break;       /* iload */
            case 0x1a: case 0x1b: case 0x1c: case 0x1d:
                emit_push_local(op - 0x1a); pc++; break;               /* iload_0..3 */
            case 0x36: emit_pop_local(bc[pc+1]); pc += 2; break;        /* istore */
            case 0x3b: case 0x3c: case 0x3d: case 0x3e:
                emit_pop_local(op - 0x3b); pc++; break;                /* istore_0..3 */
            case 0x60: e1(0x58); eN("\x01\x04\x24",3); pc++; break;     /* iadd: pop rax; add [rsp],eax */
            case 0x64: e1(0x58); eN("\x29\x04\x24",3); pc++; break;     /* isub: pop rax; sub [rsp],eax */
            case 0x68: e1(0x58); eN("\x0F\xAF\x04\x24",4);              /* imul: pop rax; imul eax,[rsp] */
                       eN("\x89\x04\x24",3); pc++; break;              /*       mov [rsp],eax */
            case 0x74: eN("\xF7\x1C\x24",3); pc++; break;              /* ineg: neg dword [rsp] */
            case 0x84: { /* iinc idx, const:  add dword [rdi+8*idx], imm32 */
                int idx = bc[pc+1]; int32_t c = (int8_t)bc[pc+2];
                e1(0x81); e1(0x47); e1((unsigned char)(8*idx)); e_i32(c); pc += 3; break; }
            case 0x59: eN("\xFF\x34\x24",3); pc++; break;              /* dup: push [rsp] */
            case 0x57: eN("\x48\x83\xC4\x08",4); pc++; break;          /* pop: add rsp,8 */
            case 0xa7: emit_jmp(pc + rd_s16(bc+pc+1)); pc += 3; break;  /* goto */
            /* if<cond> vs 0: pop rax; test eax,eax; jcc */
            case 0x99: case 0x9a: case 0x9b: case 0x9c: case 0x9d: case 0x9e: {
                e1(0x58); eN("\x85\xC0",2);
                static const unsigned char cc[] = {0x84,0x85,0x8C,0x8D,0x8F,0x8E}; /* eq ne lt ge gt le */
                emit_jcc(cc[op-0x99], pc + rd_s16(bc+pc+1)); pc += 3; break; }
            /* if_icmp<cond>: pop rax(v2); pop rcx(v1); cmp ecx,eax; jcc */
            case 0x9f: case 0xa0: case 0xa1: case 0xa2: case 0xa3: case 0xa4: {
                e1(0x58); e1(0x59); eN("\x39\xC1",2);
                static const unsigned char cc[] = {0x84,0x85,0x8C,0x8D,0x8F,0x8E}; /* eq ne lt ge gt le */
                emit_jcc(cc[op-0x9f], pc + rd_s16(bc+pc+1)); pc += 3; break; }
            case 0xac: e1(0x58); e1(0xC3); pc++; break;                /* ireturn: pop rax; ret */
            default:
                fprintf(stderr, "jit: unsupported opcode 0x%02x at pc=%d\n", op, pc);
                return NULL;
        }
    }
    NOFF[n] = LEN;

    /* patch branch rel32s */
    for (int i = 0; i < NFIX; i++) {
        int tgt = NOFF[FIX[i].target_pc];
        if (tgt < 0) { fprintf(stderr, "jit: bad branch target pc=%d\n", FIX[i].target_pc); return NULL; }
        int32_t rel = tgt - (FIX[i].off + 4);
        memcpy(CODE + FIX[i].off, &rel, 4);
    }

    void *mem = mmap(NULL, 4096, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) return NULL;
    memcpy(mem, CODE, (size_t)LEN);
    __builtin___clear_cache((char*)mem, (char*)mem + LEN);
    return (jitfn)mem;
}

int main(void) {
    /* square(x) = x*x :  iload_0, iload_0, imul, ireturn */
    uint8_t square[] = { 0x1a, 0x1a, 0x68, 0xac };
    jitfn f = jit(square, sizeof square);
    int64_t L[16] = {0}; L[0] = 7;
    printf("square(7)   = %d  (expect 49)\n", f(L));

    /* sum 1..n:  local0=n; local1=sum=0; local2=i=1; while(i<=n){sum+=i; i++;} return sum;
     * bytecode (indices: n=0, sum=1, i=2):
     *  0: iconst_0        (0x03)
     *  1: istore_1        (0x3c)
     *  2: iconst_1        (0x04)
     *  3: istore_2        (0x3d)
     *  4: iload_2         (0x1c)          <-- loop head (pc=4)
     *  5: iload_0         (0x1a)
     *  6: if_icmpgt +13 -> pc 19 (0xa3 00 0d)
     *  9: iload_1         (0x1b)
     * 10: iload_2         (0x1c)
     * 11: iadd            (0x60)
     * 12: istore_1        (0x3c)
     * 13: iinc 2, 1       (0x84 02 01)
     * 16: goto -12 -> pc 4 (0xa7 ff f4)
     * 19: iload_1         (0x1b)
     * 20: ireturn         (0xac)
     */
    uint8_t sum[] = {
        0x03, 0x3c, 0x04, 0x3d,
        0x1c, 0x1a, 0xa3, 0x00, 0x0d,
        0x1b, 0x1c, 0x60, 0x3c,
        0x84, 0x02, 0x01,
        0xa7, 0xff, 0xf4,
        0x1b, 0xac
    };
    jitfn g = jit(sum, sizeof sum);
    for (int nn = 0; nn <= 10; nn += 5) { L[0] = nn; printf("sum(1..%d)   = %d  (expect %d)\n", nn, g(L), nn*(nn+1)/2); }

    printf("code sizes: square=%d bytes, sum=%d bytes\n", 8 /*approx*/, LEN);
    return 0;
}
