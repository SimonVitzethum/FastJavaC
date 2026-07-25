# TODO — everything not yet fully done, by importance

Sorted by how much each item unblocks toward the goal (run any Java / Paper / Minecraft).
See RUN-ANY-JAVA.md for the mental model and MC-PAPER-ROADMAP.md for the long arc.
Status: 🟡 partial · ⬜ not started. (Done items are not listed.)

---

## P0 — Foundational: gate everything else

- ⬜ **Compile/bridge the full JDK (`java.base` ≈ 7357 classes).** The single biggest item.
  Compile the pure-Java classes (java.util is ~pure) + provide the ~466 native leaves (P1).
  Must be one closed world (the closure of any real class explodes — JDK-SPIKE.md).
- 🟡 **Full `invokedynamic` / `MethodHandles` / `VarHandle`.** Closed-world shapes done
  (lambda, record, type/enum switch, string-concat); the general `MethodHandle`/`VarHandle`
  runtime machinery is missing — every `java.util.function` lambda in the JDK needs it.
- 🟡 **Full reflection.** Have: `forName`/`getName`/`getSimpleName`/`newInstance`/`isInstance`/
  `isAssignableFrom`. Missing: `getDeclaredMethods`/`Fields`/`Constructors`, `Method.invoke`,
  `Field.get`/`set`, `Constructor.newInstance` — the JNI-callback infra + FjcClass registry
  can power these.
- 🟡 **Tier-1 JIT: symbolic resolution + remaining opcodes** so it can compile *arbitrary*
  loaded bytecode (not just self-contained methods). This is the load-any-jar unlock.
  - ⬜ `getstatic` / `putstatic` — needs the backend to publish static-field storage
    addresses in the FjcClass registry (currently only instance-field offsets are there).
  - ✅ `instanceof` (resolves the class → vtable[2] TypeDesc → `jrt_instanceof` walk)
  - ⬜ `invokedynamic` in the JIT (bootstrap)
  - ✅ `idiv`/`irem`/`ldiv`/`lrem` (call the checked leaves — div-by-zero throws, no SIGFPE)
  - ✅ typed float/double arrays (`faload`/`daload`/`fastore`/`dastore` — raw-bit moves)
  - ✅ `fcmp`/`dcmp` (NaN l/g variants via the comparison leaves)
  - ✅ `ldc`/`ldc_w` int/float constants (narrow constant-pool reader)
  - ✅ resolve `new`/`getfield`/`putfield`/`invoke*`/`instanceof` against the registry in the
    JIT-run harness too (the full CpInfo is now built there, not only in defineClass)

## P1 — Core completeness (broadly useful, bounded)

- 🟡 **`JVM_*` interface wiring (157 fns)** so the JDK's own `libjava`/`libnio`/`libnet` run
  unmodified through the JNI bridge (proven for `libzip`). Most are thin adapters onto
  existing runtime services (arraycopy, defineClass→JIT loader, reflection→registry, clone/
  monitors→RC); ~79 are genuine VM work (constant-pool, stack-walk, class def).
- 🟡 **String/StringBuilder intrinsic completeness** (the modeled core shadows these with
  gaps, e.g. `StringBuilder.append(F)`), and a **UTF-8 char decoder** (java.io readers are
  currently ASCII/Latin1 1:1).
- 🟡 **JNIEnv remainder:** `GetStaticFieldID`/`GetStatic<T>Field`/`SetStatic<T>Field`;
  **native-thrown exceptions propagating to Java** (`Throw`/`ThrowNew` currently no-op the
  pending model); per-lib symbol-resolve cache instead of global.
- ⬜ **`Object.clone()` for non-array objects** (shallow copy + ref-field retain).
- ⬜ **`Integer.TYPE`/`Long.TYPE`/… (`int.class` → `getstatic`)**; `Class.getComponentType`,
  `Class.getEnclosingClass`, etc. (reflection generality beyond the current subset).
- ⬜ **`Unsafe.arrayBaseOffset`/`arrayIndexScale`** (rounds out the Unsafe family).
- 🟡 **Threading robustness:** fix the **threaded-lambda crash** (fully in-process socket
  loopback — server thread + client sharing stream objects via a captured lambda —
  segfaults; an RC-across-threads / threaded-lambda bug, not the socket layer). Broader
  concurrency + memory-model coverage.
- ⬜ **`java.io.File`** operations (`exists`/`length`/`delete`/`mkdir`/`isFile`/`isDirectory`)
  and `available`/`skip`, `FileDescriptor` ctors.

## P2 — Paper (server) path

- ⬜ **`sun.nio.ch` (selectors / epoll / channels)** — the async NIO transport Netty needs.
  Blocking sockets are done (hand-written); this is the async layer (native leaves via the
  bridge or hand-written).
- 🟡 **Scale dynamic plugin loading** (the JIT + `defineClass` path exists; needs P0's JIT
  resolution to load real plugin jars).
- ⬜ **Boot the paperclip launcher → server jar → plugins** against the compiled JDK; harvest
  the reachable native-leaf list by running Paper on a reference JVM (MC-PAPER-ROADMAP §7).
- ⬜ Compile a JDK-heavy pure-Java program end-to-end to 0-live-heap (JDK-SPIKE milestone 2,
  gated on the full JDK).

## P3 — Minecraft (modded client) path

- ⬜ **Fabric Loader + Sponge Mixin + ASM: runtime bytecode transformation.** The knot
  classloader loads classes, ASM rewrites them, Mixin weaves — needs the JIT+`defineClass`
  (P0) to compile the transformed bytecode at load time. Heaviest dynamic-loading item.
  ASM/Mixin are pure Java (compilable).
- ⬜ **Compile the MC client jar + mods** (10,952 classes + fabric-api + kotlin + 12 mods,
  measured on the real 26.2 instance) as a closed world / via dynamic loading.
- 🟨 **Real GPU + display** (X11/Wayland + an OpenGL driver) — **hardware, not code.** The
  LWJGL software path is already done (System.load + auto-bind + libffi + JNIEnv, verified on
  real liblwjgl/libglfw).

## P4 — Quality / minor / cleanup

- ⬜ JIT: `>6-arg` calls (stack args, currently skipped), full exception semantics (uncaught
  propagation across methods, per-pc stack-depth reset, type-narrowed catches).
- ⬜ JNI: `>512` local refs/frame silently unregistered (grow or spill); `GetObjectClass`
  returns NULL for builtins with special vtables (String/Integer).
- ⬜ Two parallel legacy paths could be retired now that stubs exist (any residual per-class
  intrinsics superseded by the general stub + `__fjc_` mechanism).
- ⬜ `%g` double formatting is not Java's shortest round-trip form (DESIGN.md §6).
- ⬜ Broaden the modeled/stub stdlib surface (`java.util.Scanner`, `PrintWriter`,
  `DataInput/OutputStream`, more `java.util` collections) as needed by real code.

---

### One-line status

The **mechanism** is largely built (JNI/native bridge ✅, LWJGL software ✅, most bytecode ✅,
dynamic-loading mechanism ✅). The remaining work is **breadth** (the JDK) and the
**dynamic-Java features** (P0) — bounded, no unbounded piece. Suite: 106/106 green.
