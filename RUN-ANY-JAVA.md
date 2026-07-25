# What it takes: Minecraft, Paper, and *any* Java program

A synthesis of the whole effort. The claim of this file is a mental model: **running
arbitrary Java natively is two finite halves plus linking** — not an unbounded problem.
Everything we built slots into one of the three, and what remains is bounded (if large).

```
run any .jar  =  A. execute the bytecode        (finite: ~200 opcodes)
              +  B. the native methods           (finite: ~a few hundred leaves)
              +  C. linking / class loading       (closed-world OR dynamic)
```

Legend below: ✅ done · 🟡 partial · ⬜ not started.

---

## A. Execute the bytecode — nearly done

The JVM instruction set is a *fixed* ~200 opcodes. Two executors:
- **AOT** (fastjavac frontend → LLVM): ✅ covers essentially all opcodes (the JDK census found 0 gaps after i2b/i2c/i2s/dup_x1). Closed-world devirt, RC, escape analysis.
- **Tier-1 JIT** (in-runtime copy-and-patch, for code loaded at runtime): 🟡 int/long/float/double, arrays (incl. typed float/double), control flow, calls, exceptions, shifts/bitwise/conversions, `ldc`/`ldc_w`/`ldc2_w`, `idiv`/`irem`/`ldiv`/`lrem` (checked), `fcmp`/`dcmp`, `instanceof`, and `new`/`getfield`/`invoke*` resolved against the registry in both the defineClass and JIT-run paths. Gaps: `getstatic`/`putstatic` (needs static-field addresses in the registry), `invokedynamic`.

**Needed for "any program":** finish the JIT gaps + wire its symbolic resolution
(getstatic/invoke resolve against the FjcClass registry) so it can compile arbitrary
loaded bytecode, not just self-contained methods.

## B. The native methods — the bridge is done; the leaves are the work

Native methods have *no bytecode*; they must be provided. The whole JDK's native surface
is ~466 leaves (measured: libjava 209, libnio 198, libnet 32, libzip 27) — **finite, and
already implemented in the JDK's own `.so` files.**

- **JNI bridge:** ✅ **complete** for the data+control surface — auto-bind any `native`
  method (static+instance) to its `Java_*` symbol, `System.load`, libffi call of any
  signature, and a JNIEnv over fastjavac's object model + registry: classes, fields,
  refs (RC-correct local-ref frames), strings, arrays, method callbacks (all 3 forms),
  `NewObject`. Proven end-to-end on real `libzip` (CRC32/Adler32), `liblwjgl`, `libglfw`.
- **The leaves themselves:** two ways, both proven:
  - hand-written (✅ file I/O, sockets, Unsafe CAS/memory, core `Object/System/Class`),
  - **bridged to the JDK's own libs** via the JNI + `JVM_*` interface (✅ proven: dlopen
    real `libjvm.so` for its `JVM_*`, call real `libzip` CRC32 from compiled Java).
- **The `JVM_*` interface:** 🟡 `libjava` imports 157 versioned `JVM_*` upcalls. Most are
  **thin adapters onto services fastjavac already has** (`JVM_ArrayCopy`→jrt_arraycopy,
  `JVM_DefineClass`→the JIT class-loader, reflection→the registry, `JVM_Clone`/monitors→RC);
  ~79 are genuine VM work (constant-pool, stack-walk, class def). Wiring these lets the
  JDK's own native libs run unmodified.

**Needed:** either hand-write the *reachable* leaf subset (harvested by running the target
on a reference JVM), or wire the `JVM_*` table and dlopen libjava/libnio/libnet. Either is
bounded.

## C. Linking / class loading — both mechanisms exist

- **Closed-world AOT:** ✅ works, but needs *every* referenced class present → the
  "closure explosion" (any real JDK class pulls in much of java.base). Good for a
  self-contained program compiled whole.
- **Dynamic / open-world:** 🟡 the Tier-1 JIT + `defineClass` load a `.class`/`byte[]` at
  runtime and register it (FjcClass registry, dispatch by name). This is the path for
  plugins/mods/ASM. Needs the JIT resolution (B/A) completed to load arbitrary jars.

---

## What EVERY Java program needs (the shared foundation)

| Item | Status | Note |
|---|---|---|
| Full bytecode (AOT+JIT) | 🟡 | A above — finish JIT gaps |
| **The full JDK** (java.base ≈ 7357 classes) | ⬜ | compile the pure-Java classes (java.util is ~pure) + the ~466 native leaves (B). The single biggest item. |
| **invokedynamic / MethodHandles** | 🟡 | closed-world lambda/record/switch shapes ✅; the general `MethodHandle`/`VarHandle` machinery for dynamic cases ⬜ (every `java.util.function` lambda in the JDK) |
| **Full reflection** | 🟡 | `forName/getName/newInstance`/`isInstance`/`isAssignableFrom` ✅; `getDeclaredMethods`/`Method.invoke`/`Field.get,set`/`Constructor.newInstance` ⬜ — the JNI-callback infra + registry can power these |
| **Dynamic class loading** | 🟡 | JIT+defineClass path ✅; scale it (C) |
| Threads, monitors, memory model | 🟡 | threads + RC + basic `synchronized` ✅ |
| GC / complete RC | ✅ | RC + cycle collector, 0-live-heap oracle |
| Strings/StringBuilder/boxing/exceptions | 🟡 | broad coverage; intrinsic completeness ⬜ |

**Bottom line for "any program":** it's the **full JDK + full indy + full reflection +
dynamic loading**. Bounded, but the JDK is a large body of work.

## Paper (server) — the shared foundation, plus

| Item | Status | Note |
|---|---|---|
| Everything above (esp. full JDK) | ⬜ | the gate |
| **Netty** async networking → `sun.nio.ch` | 🟡 | blocking sockets ✅ (hand-written); selectors/epoll/channels ⬜ (native leaves via bridge or hand-written) |
| **Dynamic plugin loading** | 🟡 | the JIT+defineClass path |
| Rendering / LWJGL / GPU | — | **not needed** (server is headless) |

Paper is "the full JDK + Netty/nio + dynamic plugin loading, no graphics." Large but
bounded; no GPU or bytecode-rewriting mod framework in the base case.

## Minecraft (modded client) — Paper's needs, plus

| Item | Status | Note |
|---|---|---|
| Everything for a program + the JDK | ⬜ | |
| **LWJGL** (GL/GLFW/AL bindings) | ✅ | software path done — `System.load` + auto-bind + libffi + JNIEnv; verified on real `liblwjgl`/`libglfw` |
| **A real GPU + display** (X11/Wayland + GL driver) | — | **hardware**, not code |
| **Fabric Loader + Sponge Mixin + ASM** | ⬜ | **runtime bytecode transformation**: the knot classloader loads classes, ASM rewrites them, Mixin weaves — needs the JIT+defineClass (A/C) to compile the transformed bytecode at load time. The heaviest dynamic-loading requirement. ASM/Mixin are pure Java (compilable). |
| **MC client jar + mods** | ⬜ | 10,952 classes + fabric-api + kotlin + 12 mods (measured on the real 26.2 instance) |

Modded MC = Paper's Java stack + LWJGL (done) + a GPU + Fabric/Mixin/ASM runtime
transformation + ~15k mod/MC classes. The maximal, JVM-scale target.

---

## Honest effort estimate

- **The mechanism is largely built.** JNI/native bridge (done), LWJGL software (done),
  most bytecode (done), the dynamic-loading *mechanism* (JIT+defineClass, done). None of
  these is the blocker anymore.
- **The mass is the JDK + the dynamic-Java features.** Compiling/bridging the whole JDK,
  completing invokedynamic/MethodHandles and reflection, and scaling the JIT to load
  arbitrary jars — bounded, but a large body of work (roughly: **Paper ≈ the full JDK +
  Netty/nio + dynamic loading; MC ≈ Paper + LWJGL(done) + Fabric/Mixin + a GPU**).
- **Order of magnitude:** each of these is real but finite. The whole is a multi-person-year,
  JVM-scale effort — but with **no unbounded piece**: every remaining item is a known, sized
  interface (the JDK's classes, the ~466 native leaves, the JVM_*/JNI tables, the JIT
  opcodes, the MethodHandle/reflection APIs).

The thing this project proved: the two hard-looking halves — *native interop* and *bytecode
execution* — are done or bounded, and the JDK's own native code can be reused unmodified.
What's left is breadth (the JDK) and the dynamic-Java features, not a wall.
