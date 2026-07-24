# Feasibility Report: FastJavaC → Modded Minecraft, Paper, and Dynamic Jar Loading

**Date:** 2026-07-24
**Scope of request:** Extend the compiler so it can (a) compile modded Minecraft
scripts/mods, (b) compile Paper servers, and (c) support dynamic loading of jars
it compiled.

---

## 1. Verdict up front

| Goal | Verdict | Why |
|---|---|---|
| **Dynamic loading of FastJavaC-compiled jars** | **Achievable** as a bounded, native plugin ABI (`.so` + `dlopen` + stable cross-module ABI). Not achievable as JVM-style bytecode class loading. | Requires giving up the closed-world *soundness* guarantees, but the mechanism (load a compiled module into a running binary) is well-defined and buildable. |
| **Compile modded Minecraft (Fabric/Forge/NeoForge)** | **Not achievable** by extending this compiler. | Mod loaders synthesize classes at runtime (Mixin/ASM). There is no static bytecode to AOT-compile; the program does not exist until the JVM builds it. |
| **Compile Paper** | **Not achievable** by extending this compiler. | Paper rewrites bytecode at boot and loads plugins dynamically via `URLClassLoader`; depends on ~the entire JDK + `Unsafe` + JNI. |

The first goal is a real feature I can build. The second and third are not "missing
features" — they contradict the compiler's founding invariant. This report explains
exactly where and why, so the decision is fully informed.

---

## 2. What FastJavaC is (and why that matters here)

Pipeline: `.class`/`.jar` → parser → mid-level SSA IR → LLVM IR text → `clang` → native binary.

Its distinguishing feature is **not** "compiles Java" — many things do that. It is
**sound, GC-free, closed-world compilation**: no garbage collector, no `unsafe`, with
correctness checked by a 0-live-heap oracle. That is delivered by four whole-program
analyses in `crates/solver`, **every one of which requires knowing the complete set of
classes before compilation begins**:

- **Devirtualization** (RTA + CHA) — needs the full class hierarchy.
- **Escape analysis → stack allocation** — needs every call site of every object.
- **Reference-counting elision + cycle-collector omission** — needs the whole object graph.
- **Bounds-check elision**.

## 3. Where the closed-world invariant is encoded (concrete)

This is not a stylistic assumption; it is load-bearing and explicit in the code:

- **Driver collects *all* classes, then lowers.** Two-phase: register every class,
  *then* lower, because "field/method resolution crosses class boundaries."
  → `crates/driver/src/main.rs:78-106`
- **Solver is Rapid Type Analysis over a closed root set.** Entry is `java_main`;
  with no entry point, "everything is a root" (library mode). Devirtualization is
  documented as "sound **under closed world**."
  → `crates/solver/src/lib.rs:1-10`, `:55-96`
- **The frontend hard-errors on anything outside the given class set:**
  - `new C` where `C` not in input → `crates/frontend/src/lib.rs:1734`
  - `invokeinterface` on an interface not in input → `:2519`
  - `Class.forName` with a **non-constant** argument → `:2568`
  - reflection generally: "must be statically resolvable" → `:2113`
- **`invokedynamic` is handled for exactly 4 shapes** — string concat, lambda
  (`LambdaMetafactory`), records (`ObjectMethods.bootstrap`), pattern switch
  (`SwitchBootstraps.typeSwitch`). Anything else errors.
  → `crates/frontend/src/lib.rs:2180-2388`
- **Cycle-collector omission depends on proving the *entire* type graph acyclic.**
  A single dynamically-loaded class voids the proof.
  → `crates/solver/src/lib.rs:47-50`, driver `main.rs:110-136`, `-DFASTLLVM_NO_CYCLES`
- **The "stdlib" is 24 hand-written files** of a minimal `java.util`
  (`stdlib/java/util/`). The real JDK is ~20,000 classes.

**Consequence:** the moment a class can appear at runtime, RTA reachability,
CHA devirtualization, escape results, and the acyclicity proof are all *unsound*.
Dynamic loading and the current soundness model are mutually exclusive by construction.

## 4. Requirement-by-requirement analysis

### 4.1 Dynamic loading of compiled jars

Two very different things share this name:

1. **JVM-style dynamic class loading** (load `.class` bytes, define a class, link it,
   run its `<clinit>`, make it visible to reflection). This needs a bytecode
   verifier + linker + JIT/interpreter at runtime — i.e. a JVM. Out of scope.

2. **Native module loading** (compile a jar to a shared object, `dlopen` it into a
   running FastJavaC binary, resolve a stable ABI). **This is buildable.** See §6.

The catch for (2): a separately-compiled module cannot be closed-world-analyzed
together with the host. So a module ABI forces:
- cycle collector **always on** (no `-DFASTLLVM_NO_CYCLES`);
- **no cross-module devirtualization/inlining/escape** (calls across the boundary go
  through vtables and real retain/release);
- a **stable, versioned ABI** for object headers, vtable slot layout, string/array reps,
  and exception propagation — currently these are internal and free to change per build
  (`crates/backend/src/lib.rs` computes vtable slots from `Program::classes` each run).

### 4.2 Modded Minecraft

Blocking mechanisms, each fatal independently:

| Mechanism | Where it breaks |
|---|---|
| **Mixin / ASM runtime bytecode generation** (Fabric, Forge, NeoForge all use it) | Classes are synthesized during boot. Nothing static to compile. No AOT compiler can target code that doesn't exist yet. |
| **Dynamic classloaders** (`KnotClassLoader`, transforming loaders) | Violates closed world at the most basic level. |
| **`sun.misc.Unsafe`, full `MethodHandles`/`invokedynamic`** | Frontend supports 4 indy shapes; MC/loaders use the general mechanism + `Unsafe` memory ops. `crates/frontend/src/lib.rs:2388`. |
| **JNI / native libs** (LWJGL, Netty native transport, native crypto) | No JNI bridge exists in `runtime.c`; these are native `.so`s expecting a real JVM. |
| **~The whole JDK** (`java.nio`, `java.net`, `java.util.concurrent`, `java.lang.reflect`, …) | 24-file stdlib vs. thousands of required classes, many with native/`Unsafe` internals. |
| **Non-constant reflection everywhere** | Only constant-arg reflection resolves. `:2113`, `:2568`. |

### 4.3 Paper

Everything in 4.2, plus: Paper **rewrites Bukkit/CraftBukkit bytecode at startup**
and loads plugins at runtime via `URLClassLoader`. It is, by design, a dynamically
self-modifying program on a full JVM.

## 5. What breaks what — summary matrix

| Runtime capability needed | Devirt (RTA/CHA) | Escape/stack-alloc | RC elision | Acyclic proof | Frontend today |
|---|---|---|---|---|---|
| Load class at runtime | ✗ unsound | ✗ unsound | ✗ unsound | ✗ voided | errors |
| Runtime bytecodegen (Mixin/ASM) | ✗ | ✗ | ✗ | ✗ | no path |
| General reflection | ✗ | ✗ | — | — | errors on non-const |
| General `invokedynamic`/`Unsafe` | partial | — | — | — | 4 shapes only |
| JNI/native libs | — | — | — | — | none |

## 6. What IS buildable — a native plugin ABI (the achievable core of goal (a))

A concrete, bounded deliverable that honestly satisfies "dynamic loading of jars it
compiled," done the native way:

**Design sketch**
1. **`--emit-module` mode** in the driver: compile a jar to a position-independent
   shared object (`clang -shared -fPIC`) instead of an executable, exporting:
   - `fjc_module_init(FjcHostTable*)` — receives host callbacks (`jrt_alloc`,
     `jrt_retain`, `jrt_release`, exception hooks, the interned-string table);
   - `fjc_module_manifest` — a static descriptor: provided classes, their vtable
     layouts, required host ABI version.
2. **Freeze a versioned ABI** (`FJC_ABI_VERSION`): object header layout, vtable slot
   ordering, `String`/array representations, `jrt_*` signatures the module may call.
   Today these are recomputed per build in `crates/backend`; a module ABI needs them
   pinned and header-emitted.
3. **Host loader in `runtime.c`**: `jrt_load_module(path)` → `dlopen` + `dlsym` +
   version check + `fjc_module_init`, registering the module's classes/vtables into a
   runtime class registry so host code can `new` them and call them by interface.
4. **Cross-boundary calls go through vtables + real RC.** No cross-module solver
   optimization. Cycle collector always linked in modular builds.
5. **A minimal service/registry API** so a host can look up a module-provided class by
   name and obtain an interface pointer (the safe analogue of "load a plugin").

**Cost:** medium. Roughly: ABI freeze + header emission (backend), `--emit-module`
(driver), `dlopen` loader + class registry (runtime.c), version negotiation, and a
test harness (host binary + sample module jar, extend `tests/run.sh`). Deliverable in
well-scoped increments, each independently testable against the 0-live-heap oracle
(per-module, since cross-module cycles need the collector).

**Explicitly NOT delivered by this:** loading arbitrary third-party jars that were
*not* compiled by FastJavaC, JVM bytecode loading, or reflection over module classes
by string name beyond the registry API.

## 7. Optional: broaden ordinary-Java coverage (does not reach MC/Paper)

Independently useful, but does **not** move toward Minecraft/Paper:
- Grow `stdlib/` (more `java.util`, some `java.lang`, basic `java.io`).
- Generalize `invokedynamic` beyond the 4 shapes.
- Add graceful stubs/errors for unsupported reflection instead of hard failure.

## 8. Recommendation

1. **Build the native plugin ABI (§6).** It is the real, achievable, testable core of
   your dynamic-loading goal and preserves the project's identity for the
   host + each module.
2. **Reframe or drop the MC/Paper goal.** They require a JVM + JIT + full JDK +
   runtime bytecode generation — a different, ~JVM-scale project, not an extension of
   this compiler. If the underlying want is "run some Java game/plugin logic natively,"
   the tractable version is: author that logic as plain closed-world Java (or as a
   FastJavaC module), not as a Forge/Fabric mod or a Bukkit plugin.

If you want, next step options:
- I implement §6 in increments (start with ABI freeze + `--emit-module`), or
- I prototype just the `dlopen` host loader + a two-module 0-live-heap test to prove
  the boundary end-to-end, or
- I write the detailed ABI specification (header layout, vtable contract, version
  rules) before any code.
