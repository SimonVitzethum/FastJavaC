# Roadmap: What it would take to run Paper and Modded Minecraft on FastJavaC

**Date:** 2026-07-25
**Status:** Plan only. Companion to `MC-PAPER-TEST.md` (why today's compiler cannot),
`FEASIBILITY.md`, and `DYNAMIC-RUNTIME-PLAN.md` (the M1/M2 layer already built).
**Premise (accepted):** it is theoretically possible and it is the goal, however large.
**Constraints (from the user, 2026-07-25):** **no embedded JVM** — FastJavaC itself is the
engine, code runs directly on the CPU as native machine code. **An in-process JIT IS
allowed** *provided it costs little performance and little RAM.* This resolves the central
tension below: the answer is a **copy-and-patch / template JIT** (§2), not an interpreter
and not an embedded JVM.

**Guiding principle (from the user, 2026-07-25):** *as much as possible runs as
FastJavaC-compiled native binaries; the cheap JIT is permitted to **edit those binaries at
runtime.*** So the JIT is not a separate execution engine that interprets bytecode — it is
a **native-code editor**: it (a) **splices in** new native code for classes generated at
runtime (copy-and-patch stencils, §2), and (b) **patches/specializes** existing native
code in place (Phase-5 trampolines, inline caches, guard specialization, §2 Tier 2).
Everything that *can* be AOT is AOT; the JIT only touches what must change at runtime, and
its output is native code welded into the same running image — never an interpreted tier.

---

## 0. The honest framing

"Run Paper / Modded Minecraft" is equivalent to **"provide a conforming JVM"** — because
these programs *are* JVM programs that generate and load code at runtime. So the roadmap
is a JVM-construction roadmap. That is a multi-person-year effort, but it is **bounded
and enumerable**, not infinite — the trick that makes it plannable is:

> **Do not re-implement the Java class library. Compile the real OpenJDK `.class`
> bytecode with FastJavaC.** This turns "reimplement ~20,000 classes" into "compile them
> + supply the native/intrinsic layer they bottom out in" — a large but *finite,
> listable* surface.

Concrete scale (measured locally):
- `java.base` alone: **7,357 classes**; full JDK ≈ 20k across modules.
- Native methods: ~**358 in a 1,500-class java.base sample** → on the order of
  **1,000+ native methods JDK-wide**; the reachable set for a headless server is smaller
  (hundreds) but still the real hand-written work.
- Paper ships as a **paperclip launcher (259 classes)** that downloads+patches the real
  server (thousands of classes) at boot. A single Fabric mod (Sodium) is **803 classes**
  on top of the Fabric loader + the full MC client.
- Installed JDK here is **GraalVM 25** (relevant to the "embed/reuse" strategy below).

## 1. The five capabilities that are missing (and what each requires)

| # | Capability | Why MC/Paper need it | Concrete work |
|---|---|---|---|
| A | **Execute bytecode that only exists at runtime** (Mixin/ASM/ByteBuddy/`LambdaMetafactory`/reflection Proxies generate classes in memory) | Mixin *is* runtime bytecode generation; loaders synthesize classes at boot | An in-process **execution tier** for arbitrary bytecode (see §2 — this is the one that forces revisiting "no VM/no JIT") |
| B | **The whole JDK** (`java.io/nio/net/util/util.concurrent/lang.reflect/lang.invoke`, `sun.*`, `jdk.internal.*`) | Even the launcher needs 49 JDK classes incl. `ClassLoader`, `MethodHandles` | **Compile OpenJDK's pure-Java classes** with fastjavac + implement the **native/intrinsic layer** (§3) |
| C | **Full `invokedynamic` + `java.lang.invoke`** | Lambdas, string concat, and loader/Mixin plumbing use it in full generality (today: 4 fixed shapes) | A **method-handle runtime**: bootstrap-method calls, `MethodHandle`/`MethodType`/`CallSite`, `LambdaMetafactory`, `StringConcatFactory` (§4) |
| D | **`Unsafe` + reflection + a compatible GC** | MC and the JDK internals use `jdk.internal.misc.Unsafe`, field offsets, CAS, and pervasive reflection | Native `Unsafe` mapped to the object layout; **switch the dynamic heap to a tracing GC** (RC cannot survive raw pointer writes / reflection) (§5) |
| E | **Class loaders + JNI** | Paper/Fabric build custom `ClassLoader`s; native libs (Netty transport, zlib, crypto; LWJGL for the client) call in via JNI | A real **ClassLoader model** (delegation, per-loader namespaces, `defineClass` → execution tier) + a **JNI implementation** compatible with prebuilt `.so`s (§6) |

Everything MC/Paper-specific (Mixin, the mod loaders, Paper's boot patching) is an
*application* of A + E: if `defineClass(byte[])` works and arbitrary bytecode runs, then
Mixin/ASM "just work" — you never special-case them, you support the primitive they
stand on.

## 2. The execution tier: an in-process copy-and-patch JIT (no interpreter, no JVM)

The M2 "compile-on-load" path (subprocess `fastjavac` → cached `.so` → `dlopen`) handles
*known* jars. It does **not** practically handle capability A: Mixin/loaders generate
**many** classes in memory at boot; a `clang` invocation per generated class is
seconds×hundreds = unusable, and some generated code is transient. Given the constraint
"in-process JIT allowed if cheap in time and RAM," the right technology is:

> **Copy-and-patch compilation** (Xu & Kjølstad, PLDI 2021). Compile a fixed library of
> per-bytecode **stencils** *ahead of time* (with the existing LLVM/clang path, once, at
> build time). At runtime, generating a method is `memcpy` the stencils + patch a few
> immediates/relocations — **compile speed comparable to an interpreter's startup, a few
> KB of code per method, no LLVM/allocator at runtime, and machine code within ~2× of an
> optimizing JIT.** That directly satisfies "little performance, little RAM," and every
> method runs **directly on the CPU** (no interpreter loop).

**Tiered engine:**
- **Tier 0 — AOT (existing).** Sealed/known code (incl. compiled OpenJDK, M2 modules):
  full LLVM optimization. Carries the static bulk.
- **Tier 1 — copy-and-patch JIT (new).** Every runtime-generated / `defineClass`'d method
  is stencil-compiled on first call — cheap, low-RAM, native. Replaces "an interpreter."
- **Tier 2 — background re-optimization (optional, later).** Promote hot Tier-1 methods
  through the existing LLVM AOT backend on a worker thread; hot-swap via the Phase-5
  trampoline. Only for the few genuinely hot methods, so its cost is amortized.

No interpreter is needed at all: with a fast enough Tier 1, "compile every method on first
call" is cheaper than maintaining an interpreter, and keeps the "always native on the CPU"
property. This is the single biggest new subsystem, but copy-and-patch makes it tractable
and keeps the RAM/latency budget the user requires.

**This is the "JIT edits the binary" principle in practice:** the running image is a
FastJavaC native binary; Tier 1 *appends* native code (stencil-spliced generated methods)
into it, and Tier 2 *rewrites* native code in place (Phase-5 trampolines already do this;
add monomorphic inline-cache patching and guard specialization). The JIT never owns a
parallel execution model — it only edits native code that the CPU runs directly.

## 3. The JDK: compile OpenJDK + build the native layer

> **Status (2026-07-25): native layer STARTED — the atomics are DONE.** The
> `jdk.internal.misc.Unsafe`/`sun.misc.Unsafe` **int/long/reference CAS + memory family** is
> implemented against fastjavac's object model (`Program::field_byte_offset` gives
> `objectFieldOffset` a layout-exact byte offset; ops lower to `jrt_unsafe_*` `__atomic_*`
> accesses; the reference ops carry the RC store barrier). The signature-polymorphic
> **`java.lang.invoke.VarHandle`** atomics lower to the same layer (findVarHandle bound in
> `<clinit>` → folded offset → shared helpers), closing the "VarHandle pervasively" item.
> Real OpenJDK `AtomicInteger`/`AtomicLong` (Unsafe) compile+run+heap-balance, and
> `AtomicReference`'s VarHandle mechanism runs heap-balanced — the first real JDK classes with
> native methods running end-to-end. Remaining native backlog below; nearest next items:
> `Object`/`System`/`Class` core natives (`arraycopy`, `hashCode`, `getClass`, `clone`),
> `arrayBaseOffset`/`arrayIndexScale`, `Integer.TYPE` (`int.class`), then `java.io`/`nio`.

- **Compile the pure-Java OpenJDK classes** (from `jmods`/`src`) with fastjavac. Most of
  `java.util`, `java.io`, `java.nio`, `java.util.stream`, `java.util.concurrent` is pure
  Java and should compile once the language/bytecode coverage is complete.
- **Implement the native/intrinsic layer** these bottom out in — the real hand-written
  work, enumerable from the `native` methods + HotSpot intrinsics:
  - `System.arraycopy`, `Object.getClass/hashCode/clone/wait/notify`, `Class.*` reflection
    primitives, `Thread.*`, `Runtime.*`.
  - `java.io`/`java.nio` → real syscalls (files, sockets, epoll/selectors, mmap).
  - `sun.nio.ch.*` (channels/selectors — Netty NIO transport needs these).
  - `jdk.internal.misc.Unsafe` / `sun.misc.Unsafe` (§5), `jdk.internal.reflect.*`.
  - crypto/zlib/charset intrinsics (or link the platform libs).
- **Bootstrapping**: class-init ordering, the primordial/bootstrap loader, module system
  (or a `--illegal-access`-style flattening), verification (start "trust the input",
  harden later).
- Estimate: **hundreds of native methods** for a headless server; more with the client.

## 4. `invokedynamic` + `java.lang.invoke`

Generalize beyond today's 4 indy shapes to the full mechanism: run arbitrary bootstrap
methods, implement `MethodHandle`/`MethodType`/`VarHandle`/`CallSite`, method-handle
combinators (`insertArguments`, `asType`, …), `LambdaMetafactory`, `StringConcatFactory`.
Method handles resolve against the runtime class/method registry (the FjcClass metadata
from Phase 0 is the seed) and dispatch through the execution tier (§2). Substantial but
self-contained subsystem; prerequisite for essentially all modern Java.

## 5. `Unsafe`, reflection, and the GC switch (soundness consequence)

- `Unsafe` gives out raw addresses, does CAS/fences, and writes fields by byte offset.
  Map it to the object layout (Phase 0 `FjcClass` already exposes field offsets + the
  ref-offset map). But `Unsafe`/reflection can store references the RC system cannot see.
- **Consequence:** the RC + acyclic-elision model (FastJavaC's core value) **cannot remain
  sound** for the dynamic heap. Plan a **tracing/moving GC for the open-world heap**,
  keeping RC only for the sealed AOT core that never escapes into `Unsafe`/reflection.
  This is a real GC implementation (safepoints, stack maps, root scanning, write
  barriers) — the FjcClass ref-offset maps give the object-tracing primitive; safepoints
  were already scoped in Phase 5.
- Honest note: this means "GC-free" no longer describes the MC/Paper workload — MC's heap
  is GC'd. RC-freedom survives only for the AOT-sealed portions.

## 6. Class loaders + JNI

- **ClassLoader model**: parent delegation, per-loader class namespaces (same name,
  different loader = different class), `defineClass(byte[])` → verify → execution tier,
  `findClass`/`loadClass`, unloading. Paper's `URLClassLoader`, Fabric's transforming
  `KnotClassLoader`, and Mixin's mixin-transformer are then ordinary users of this.
- **JNI**: the JNI function table, `System.loadLibrary`, `jobject`↔object handle mapping,
  `RegisterNatives`, exceptions across the boundary — so prebuilt native libraries work:
  - **Paper server**: Netty native epoll transport (or force NIO), zlib, crypto — a
    **small** native surface.
  - **MC client**: LWJGL (OpenGL/GLFW/OpenAL/Vulkan), stb, etc. — a **large** native
    surface + a working GL context. Much harder; server-first is the right order.

## 7. Strategy: build the engine on FastJavaC (no embedded JVM)

Per the constraint, **FastJavaC itself is the engine** — deliver A–E above with the
Tier 0/1/2 model of §2. Outcome: FastJavaC becomes an AOT+copy-and-patch JVM-equivalent
that runs everything directly on the CPU. Effort: **multi-person-year**; the JIT (§2), the
JDK native layer (§3), `invoke` (§4), the GC (§5), and JNI (§6) are each large but bounded.

**Embedding an existing JVM is out of scope** as a product (the user requires "ohne JVM").
The locally installed **GraalVM 25** is still useful as a *development oracle only*: run
Paper on it to (i) diff behavior against the FastJavaC engine and (ii) **harvest the exact
list of native methods + `invoke`/`Unsafe` call sites Paper actually exercises** — that
trace becomes the precise, prioritized work list for §3/§4/§5, so those subsystems are
built to the reachable set, not the whole JDK.

## 8. Milestone ladder (Strategy 1) — each is a real proof-point

1. **Broaden the compiler to full JVM bytecode + language** (all opcodes, generics
   erasure edge cases, nested/hidden classes). No new runtime yet.
2. **Compile a large pure-Java OpenJDK slice** and pass a JDK-heavy pure-Java test
   program (collections + streams + `java.io` + `java.nio` + `java.util.concurrent`).
   *De-risks §3's "compile OpenJDK" thesis before anything else.* **Recommended first step.**
3. **Full `invokedynamic`/`MethodHandles`** → real lambdas/string-concat/`VarHandle`.
4. **Copy-and-patch JIT (Tier 1) + `ClassLoader.defineClass`** (§2, §6) → build the
   AOT stencil library, then run a program that generates a class with ASM at runtime and
   invokes it — stencil-compiled on first call, native, low-RAM.
   *Status: STARTED.* An integer-subset copy-and-patch JIT is integrated into the runtime
   (`jrt_jit_run` in `runtime.c`, engine `spikes/jit_engine.c`, test `tests/jit.sh`): a
   `--dynamic` binary reads a `.class` at runtime, extracts a method's bytecode with a
   minimal in-C classfile parser, copy-and-patch-compiles it to native x86-64, and runs it
   (incl. loops/branches) — no AOT of that method, no subprocess. The **`defineClass(byte[])`
   entry is also done** (`jrt_jit_raw` for a raw method blob, `jrt_define_and_run` for an
   in-memory class file, `tests/jitmem.sh`): bytecode a program generates in memory at
   runtime is JITted to native code in-process — the bridge to ASM/Mixin. The stencil set
   now also covers **references** (aload/astore/areturn, if_acmp, ifnull) and **64-bit
   longs**; **object arguments** flow into JITted methods; and a **JIT ClassLoader**
   (`jrt_define_class_jit`) registers JITted methods into the FjcClass registry so they
   **dispatch by name** like any AOT/module class (`jrt_call_static`, `tests/jitclass.sh`).
   The stencil set now also covers **double arithmetic** (xmm: dadd/dsub/dmul/ddiv,
   i2d/d2i, dreturn), **exceptions** (athrow → handler dispatch via the exception table,
   checkcast no-op), **object returns** with an RC retain barrier, and **field access**
   (getfield/putfield with offsets resolved from the FjcClass registry via the constant
   pool), **method calls** (invokestatic + invokespecial, incl. self/mutual recursion, via
   a callee frame-setup convention + two-pass class registration), **object creation**
   (`new` + `<init>`, RC-correct for the factory create-and-return pattern), and **float**
   (32-bit xmm). JIT-defined classes call each other and dispatch by name. Tests:
   `tests/jit{class,field,new,virtual}.sh`. **invokevirtual/invokeinterface are now in**
   (`tests/jitvirtual.sh`): a JIT-defined method dispatches through the receiver's runtime
   vtable, and open-world builds keep all virtual methods as roots so their vtable slots
   aren't pruned to null.
   **Both prior blockers for mod-style code are now solved for the common case:**
   1. **JIT-side reference counting — DONE** (`tests/jitrc.sh`). The JIT prologue holds the
      locals base in RBX (callee-saved, so C calls preserve it); a compile-time ownership
      model marks only `new` results as owned; owned ref-locals are released at
      ireturn/lreturn/return. So a JITted method that `new`s objects no longer leaks (0-live
      oracle holds). Conservative — never over-releases.
   2. **JIT↔AOT native calling convention — DONE for AOT callees** (`tests/jitabi.sh`).
      JIT→AOT calls (invokestatic/special/virtual) marshal <=6 int/ref args into the native
      registers (arg0→RDI…), so AOT methods/constructors that use `this` or read/write fields
      get the correct receiver. FjcMethod flag bit2 tags JIT-defined (locals-array) vs AOT
      (native) callees. Combined with (1), the mod-critical chain works end to end: a JITted
      method `new`s an object, its AOT constructor sets a field via the correct `this`, a
      virtual getter reads it, and the object is RC-freed — heap balances.
   **Arrays — DONE** (`tests/jitarr.sh`): int/reference array creation (newarray/anewarray),
   element load/store (iaload/iastore/aaload/aastore via bounds-checking runtime helpers),
   and arraylength; new arrays are RC-owned and freed. `@main` publishes the array vtables
   to runtime globals so JITted code can allocate.
   **Float/double call args + results — DONE** (`tests/jitfloat.sh`): the JIT↔AOT native
   marshaller is descriptor-driven (int/ref/long→RDI..R9, float/double→XMM0..7), results are
   read from RAX or XMM0 by return type, and RC release is wired into dreturn/freturn.
   **Reverse AOT→JIT + fully JIT-defined polymorphic subclasses — DONE** (`tests/jitmod.sh`).
   JITted methods now have a **native entry** (the prologue allocates a stack locals frame,
   points RBX at it, and spills the incoming native arg registers — int/ref/long from
   RDI..R9, float/double from XMM0..7 — per descriptor + max_locals + static-ness). Every
   invoke native-marshals for all callees (code loaded via &FjcMethod so recursion/forward
   refs resolve), and every invoker calls JIT methods with native args. So **JIT and AOT are
   now ABI-identical in both directions**: a JIT-defined class can extend an AOT class,
   override methods (installed in the inherited vtable), be `new`'d, and have its overrides
   dispatched virtually by AOT *or* JIT code — the mod/Mixin pattern, RC-freed and
   heap-balanced. **Only minor items remain:** >6-arg calls (stack args; such methods are
   currently just not JITted — a safe skip) and full exception semantics (uncaught
   propagation across method boundaries, per-pc stack-depth reset for deep throws,
   type-narrowed catches). The Tier-1 JIT is otherwise a working execution engine for the
   int/long/float/double + reference + array + control-flow + call + exception subset, with
   correct RC and JIT↔AOT interop.
5. **`Unsafe` + tracing GC for the dynamic heap** (§5) → `Unsafe`/reflection-heavy program
   balances and survives GC.
6. **JNI + NIO/Netty native** (§6) → a trivial Netty echo server runs.
7. **Boot Paper to the console** (paperclip → real server → "Done!"), NIO transport.
8. **Paper accepts a login / runs a tick**, then a **simple Bukkit plugin** loads.
9. **A Fabric mod loads under a transforming loader + Mixin** (server-side).
10. **(Optional, much later) MC client**: LWJGL/JNI + a GL context.

Reaching **Paper server ("Done!")** is milestone 7 — that is the tractable headline
target. The MC *client* (10) is a separate, much larger native-graphics project.

## 9. Effort & risk summary

- **Biggest new subsystems:** copy-and-patch JIT (§2), JDK native layer (§3), tracing GC
  (§5), JNI (§6), `invoke` (§4). Each is weeks–months of focused work.
- **Biggest risk / value tradeoff:** §5 — supporting `Unsafe`/reflection forces a GC and
  gives up the RC-soundness that is FastJavaC's differentiator for the dynamic heap. The
  copy-and-patch JIT (§2) does **not** carry this risk; the RAM/latency budget is met by
  construction (stencils are AOT-built; runtime cost is memcpy+patch).
- **Two cheap de-riskers, do both first:** (i) milestone 2 — compile a large OpenJDK slice
  + run a JDK-heavy pure-Java program; (ii) a **copy-and-patch spike** — one stencil set,
  compile+run one method at runtime, measure compile time and code size. Together they
  validate or kill the two central theses (compile-OpenJDK, cheap-JIT) before committing
  to the GC/JNI/`invoke` build-out.

## 9a. Milestone-2 spike DONE — result (see JDK-SPIKE.md)

**Executed 2026-07-25.** Key results, which reprioritise the ladder:
- You **cannot** compile a small JDK slice: the closed-world closure of any real class
  explodes (`Objects` → `AssertionError` → `Comparator` → `function.*` lambdas → …). The
  JDK must be compiled as **one whole closed world**.
- With the whole `java.base` (7,357 classes) as the closed world, the first wall is a
  **real feature** (`Class.getCanonicalName` — reflection generality), not a missing class.
  So the residual backlog is finite/enumerable: reflection generality, **full indy**,
  the native layer, core-model completeness (full exception hierarchy + String/StringBuilder),
  parser robustness on huge constants.
- **Native-method backlog measured:** java.lang 116, java.io 48, nio.ch 133,
  jdk.internal.misc 90, java.nio 5 — but **java.util = 2 native / 485 classes** (≈pure).
- **Consequence:** milestone 2 is *gated* on **full invokedynamic/MethodHandles**
  (every `java.util.function` lambda needs it, and it's buildable without the native layer).
  → **invokedynamic is the correct next unlock, not the native layer.**

## 9b. Milestone-3 (invokedynamic) — measured & essentially CLOSED

Census of **all** invokedynamic call sites across java.base core (3789 classes, 1347 sites):

| Bootstrap factory | sites | status |
|---|--:|---|
| `LambdaMetafactory.metafactory`/`altMetafactory` | 1478+16 | ✅ handled (lambda path — **verified end-to-end** on real `java.util.function.IntUnaryOperator`, capturing lambda → correct result) |
| `ObjectMethods.bootstrap` (records) | 151 | ✅ handled |
| `SwitchBootstraps.typeSwitch` | 61 | ✅ handled |
| `SwitchBootstraps.enumSwitch` | 2 | ✅ **now handled** (this change — String label = enum-constant identity, Class label = instanceof, null→−1; test `tests/enumswitch.sh`, matches reference JVM 1/2/9/7) |
| `StringConcatFactory.makeConcat[WithConstants]` | ~18 | ✅ handled |

**Conclusion:** the invokedynamic *mechanism* is complete for practically all closed-world
Java (application, collections, streams, records, pattern/enum switch). What the spike
called "MethodHandles/VarHandle pervasively" turns out to be **signature-polymorphic method
calls, not indy** — and the base concurrency primitives bottom out in
`jdk.internal.misc.Unsafe.compareAndSet*` (a **native** method, e.g. `AtomicInteger` uses
`Unsafe.compareAndSetInt` directly, no VarHandle). So the residual "invoke" work is:
- **Signature-polymorphic `MethodHandle.invoke/invokeExact` + `VarHandle.{get,set,compareAndSet,…}`** —
  needed only by the `java.lang.invoke` internals and a few concurrent utilities; most
  app/JDK code never hits it. Deferred (deep; a dynamic mechanism, unlike the static indy above).

**Net effect on the ladder:** milestone 3 is no longer the gate. With indy closed, the JDK
gate reverts to **the native layer** (§3 — Unsafe CAS/memory, Object/System/Thread/Class,
file+socket I/O) plus **core-model completeness** and **closed-world closure**.

## 10. Recommended first concrete steps (two parallel spikes)

1. **OpenJDK-compile spike (milestone 2):** pick ~a few hundred `java.base` classes
   (collections, streams, `java.io`, `java.nio.file`, `java.util.concurrent`), compile
   them with fastjavac (fixing bytecode/language gaps as they surface), and get one
   non-trivial pure-Java program to run and 0-live-balance. Its gap list is the real
   backlog for §3.
2. **Copy-and-patch spike (milestone 4 core):** define one small stencil set, generate a
   trivial method's machine code at runtime by memcpy+patch, run it, and measure
   compile-time-per-method and bytes-per-method against the "cheap JIT" budget.

Together these validate the two load-bearing theses — *compile the real JDK* and *a JIT
that costs almost nothing* — before committing to the GC (§5), JNI (§6), and `invoke` (§4)
build-out. Run Paper on the local GraalVM in parallel purely to harvest the reachable
native-method / `invoke` / `Unsafe` list (§7).
