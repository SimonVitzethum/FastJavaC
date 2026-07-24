# Design Plan: Dynamic Loading & Self-Modification without a VM or JIT

**Date:** 2026-07-25
**Status:** Plan only — no implementation.
**Hard constraint:** No virtual machine (no bytecode interpreter) and, as far as
possible, **no in-process JIT**. All code must run as ordinary native machine code
directly on the CPU at all times.
**Goal:** Emitted FastJavaC binaries can still, *while running*, load new code, apply
mixins, load mods/plugins, and redefine their own methods — but achieved purely by
**ahead-of-time native compilation + dynamic native linking + pointer/branch
patching**, never by interpreting or JIT-compiling bytecode in-process.

> Supersedes the earlier interpreter/JIT-based draft. It reuses only the parts of that
> plan that are compatible with "native code on the CPU, no VM, no JIT."

---

## 1. The central idea: move codegen forward, keep only linking at runtime

A JVM achieves dynamism by *generating code at runtime* (interpret, then JIT). We are
forbidden from doing that. The equivalent without a VM/JIT is:

> **Everything is AOT-compiled to native code — the sealed core *and* every mod, plugin,
> and mixin (each as its own native module). At runtime the engine only (a) dynamically
> links already-native modules and (b) rewrites code pointers / branch targets to switch
> between already-native implementations.** No bytecode is ever executed by an interpreter
> and no machine code is ever generated in-process.**

This is the same principle as Android's `dex2oat` or `.so` plugins: compile *ahead of
load*, then just link. The CPU always executes real machine code.

## 2. Three operating modes (and their honest limits)

| Mode | How code arrives | VM? | JIT? | Native on CPU? |
|---|---|---|---|---|
| **M1 — Prebuilt native module** *(primary)* | Mod/plugin/mixin shipped already compiled by `fastjavac` to a `.so`/PIC object | none | none | yes, always |
| **M2 — Compile-on-load (ahead-of-load)** | Mod/plugin arrives as `.class`/`.jar` bytecode; the loader invokes `fastjavac` as a **subprocess** to produce a native module, caches it, then links it | none | none in-process (a separate compiler process, not a JIT) | yes, always |
| **M3 — Raw bytecode with no prior compilation, executed immediately** | `.class` bytes must run *without* any compile step | **required** | or JIT required | — |

**M1 and M2 satisfy the constraint. M3 does not exist without a VM or JIT — this is a
hard theoretical limit, not a missing feature:** native CPUs cannot execute JVM
bytecode; turning bytecode into CPU instructions is *exactly* what an interpreter or a
compiler does. **Decision (2026-07-25): the design delivers BOTH M1 (prebuilt native
modules) and M2 (compile-on-load for bytecode-only inputs).** M3 is explicitly excluded.

**Implication to accept:** mods/plugins/mixins are either shipped precompiled (M1) or
compiled to native the first time they are loaded and then cached (M2). They are never
run straight from bytecode by an in-process engine.

## 3. Self-modification without generating code

"Modify itself while running" is delivered by **switching between implementations that
were all AOT-compiled**, not by producing new code. Three layered mechanisms, all
CPU-native, none involving a VM or JIT:

### 3.1 Indirect method slots (pointer swap) — the primary mechanism
- Any method that may be overridden/redefined dynamically is called **through a code
  pointer in a runtime method table** (not a direct `call` to a fixed symbol). The
  vtable machinery in `crates/backend` (`vtable_slots`, `vtable_index`) already provides
  the indirection; it is extended into a mutable runtime method table.
- **Redefinition = write a new (already-native) code pointer into the slot.** The next
  call runs the new implementation. Zero codegen. Purely a store.
- Final/private/static core methods stay direct calls (fast, non-patchable).

### 3.2 Binary trampoline patching (literal self-modifying code) — optional, opt-in
- For hot direct-call sites that still must be redirectable, emit a **patch point**: a
  padded entry (NOP sled / reserved bytes) that the runtime can rewrite into a `jmp` to
  another native implementation.
- This is *literally* self-modifying machine code (rewrite instruction bytes + icache
  flush), but it **switches between pre-existing native code**, it does not synthesize
  new logic. Requires W^X handling (`mprotect` RW→RX) and cross-thread safepoints.
- Used sparingly (Mixin `@Inject` at method head/tail); pointer slots (§3.1) are the
  default because they need no code rewriting.

### 3.3 Guarded devirtualization with a native slow path — recovers lost speed
- Because dynamic subclasses can appear, the sealed core can no longer *unconditionally*
  devirtualize. Instead emit: a fast direct call **guarded** by a class-descriptor check,
  with the indirect method-table call as the fallback. When a dynamic subclass loads that
  invalidates the guard, the guard simply starts taking the (already-native) slow path.
- No deopt-to-interpreter (there is none); the fallback is just another native call.

## 4. Self-describing runtime metadata (the enabling substrate)

Unchanged in spirit from the general design and still required. For each class the AOT
backend emits a **runtime class descriptor** (`FjcClass`) into the binary:

- superclass + interface descriptors; frozen, versioned vtable/method-table layout;
- field table (name, descriptor, offset, ref/primitive) — drives GC tracing of
  dynamically loaded instances;
- method table: name, descriptor, slot, **current native code pointer**, patch-point info;
- allocation size + object header format; `FJC_ABI_VERSION`.

Two registries (static, from the core; dynamic, from the loader), keyed by internal
name; `new`, dispatch, `instanceof`, and reflection resolve through them.
`crates/backend` already computes this data (`ClassCtx`) and discards it — the change is
to **serialize it into the binary**.

## 5. Dynamic linking engine (replaces the interpreter/JIT entirely)

When a module is loaded (`fjrt` inside the binary):

**M1 path (prebuilt native module):**
1. `dlopen` the module `.so` (or a custom loader for raw PIC objects in freestanding
   builds — no libc `dlopen` there).
2. Read its exported `fjc_module_manifest`; check `FJC_ABI_VERSION`.
3. Call `fjc_module_init(host_table)` to hand over host callbacks (`jrt_alloc`,
   `jrt_retain/release`, exception hooks, the class registry, the interned-string table).
4. **Register** the module's `FjcClass` descriptors + native method pointers into the
   dynamic registry; wire vtable/interface slots to the frozen ABI.
5. Run the module's `<clinit>`s. Done — its methods are now callable, natively.

**M2 path (bytecode input, compiled ahead of load):** *(in scope — see §5.1)*
1. Hash the input jar; look up the native module in the compile cache.
2. On miss, invoke `fastjavac --emit-module` as a subprocess (this *is* AOT compilation,
   in a separate process — not an in-process JIT), producing and caching the `.so`.
3. Continue as the M1 path.

**Mixins** are applied as a **compile-time (or compile-on-load) transformation** before
native codegen (weave the mixin into the target class in `crates/frontend`/`classfile`),
*plus* the runtime pointer/trampoline swap (§3) to redirect existing core methods to the
woven native implementation. No runtime bytecode manipulation of live code.

### 5.1 M2 — the compile-on-load cache (design detail)

M2 lets a plain `.class`/`.jar` (bytecode we only receive at runtime) still run as
native code, without a VM or an in-process JIT, by compiling it *ahead of load* in a
separate `fastjavac` process and caching the result.

- **Cache location & layout.** A per-user cache dir (env override `FASTJAVAC_CACHE`,
  default `$XDG_CACHE_HOME/fastjavac` → `~/.cache/fastjavac`). Entries:
  `<key>.so` (native module) + `<key>.manifest` (ABI version, source hash, dep list).
- **Cache key = hash of all inputs that affect the output**, so a stale entry can never
  be used: content hash of the jar **+** `FJC_ABI_VERSION` **+** `fastjavac` build id
  **+** the resolved closed set of dependency modules it links against **+** relevant
  compile flags. Any change ⇒ new key ⇒ recompile. No time-based invalidation needed.
- **Compilation unit / closed world per module.** Each M2 module is compiled
  closed-world over *its own* classes plus the **already-loaded modules' descriptors** it
  references (resolved through the runtime registry and passed to the subprocess as
  `--link-against <manifest>`). Cross-module edges use the frozen ABI (vtable + real RC),
  never inlined across the boundary — so a module's cache entry stays valid regardless of
  what else loads later, as long as its dependency set (part of the key) is unchanged.
- **Concurrency.** First loader to miss takes a per-key file lock, compiles, atomically
  renames the finished `.so` into place; concurrent loaders wait on the lock, then hit.
- **Failure handling.** If the subprocess fails (unsupported feature, missing class),
  the load fails with the compiler's diagnostic — it does **not** silently fall back to
  any interpreter (there is none).
- **Security / trust.** M2 runs the FastJavaC compiler over untrusted bytecode and then
  `dlopen`s the result — i.e. it executes third-party native code in-process, exactly
  like loading any native plugin. This is a **trusted-input** model: the host decides
  which jars it compiles+loads. Sandboxing untrusted mods is a separate, later concern
  (process isolation), not solved by M2 itself. Documented as an explicit boundary.
- **Toolchain requirement.** M2 needs `fastjavac` (and its `clang`) present on the
  machine at runtime. Servers/dev boxes: fine. Freestanding/seL4 (§9.4): no subprocess,
  no `dlopen` ⇒ **M1-only** there. The runtime detects toolchain absence and reports it.

## 6. Memory management (open world)

- **Cycle collector always linked** in dynamic builds — the acyclicity proof
  (`crates/solver/src/lib.rs:47-50`) cannot hold once modules load.
- RC-elision / escape / stack-allocation apply **only inside a single AOT module**;
  across the module boundary, real `jrt_retain`/`jrt_release`.
- Dynamically loaded classes carry a **field-ref map** (from their descriptor, §4) so
  the tracer walks their instances without static knowledge.
- Redefinition keeps old instances valid under their old (versioned) layout.

## 7. Reuse map (what changes where)

| Existing piece | Role now |
|---|---|
| `crates/classfile` | Reused (parse `.class`); for M2, in the compiler subprocess — **not** embedded for in-process execution. |
| `crates/frontend` | Reused + **open-world mode** (dynamic dispatch/`new` instead of hard-erroring at `lib.rs:1734`, `:2519`) + **mixin weaving** stage. |
| `crates/ir` | Reused unchanged — the AOT lowering target for every module. |
| `crates/backend` | Add: emit `FjcClass` descriptors + method tables (§4); indirect-slot + patch-point emission (§3); `-shared/-fPIC` module output. **No new JIT backend.** |
| `crates/solver` | Scoped to single modules; adds **guarded devirtualization** (§3.3) instead of unconditional. |
| `crates/driver` | Add `--emit-module` (native `.so`), `--dynamic` build mode (link `fjrt`, always-on collector, indirect dispatch), and the M2 compile-cache subprocess logic. |
| `runtime.c` → `fjrt` | Add: module loader (`dlopen`/custom), class registries, method-table patching, W^X + safepoint support for §3.2, compile-cache lookup for M2. **No interpreter, no JIT.** |

## 8. Phased roadmap (each phase independently shippable & 0-live-heap testable)

- **Phase 0 — ABI freeze & runtime metadata.** Emit `FjcClass` descriptors + registries;
  version the ABI. *Test:* the AOT core introspects its own classes by name; oracle
  unchanged.
- **Phase 1 — Prebuilt native module ABI (M1).** `--emit-module` → `.so`; `dlopen`
  loader; cross-module vtable calls + real RC. *Test:* two-module 0-live-heap program.
  **First concrete milestone; fully satisfies "no VM, no JIT."**
- **Phase 2 — Indirect method slots + redefinition by pointer swap (§3.1).** Runtime
  method table; a module replaces a core method's slot. *Test:* a loaded module
  redefines a core method; new behavior on next call; heap balances.
- **Phase 3 — Mixin weaving + guarded devirtualization (§3.3, §5).** Compile-time/on-load
  weaving; guarded fast paths with native fallback. *Test:* a mixin overrides/injects a
  core-visible method; behavior changes; heap balances.
- **Phase 4 — Compile-on-load cache (M2).** Loader compiles bytecode jars to cached
  native modules via a `fastjavac` subprocess. *Test:* load a `.jar` (bytecode) at
  runtime; it runs natively on first and subsequent loads; cache hit second time.
- **Phase 5 — Binary trampoline patching (§3.2) + safepoints.** W^X patch points for
  in-place redirect of hot direct calls; cross-thread safepoints. *Test:* a running
  program redirects one of its own hot methods in place; heap still balances.

## 9. Principal risks / open decisions

1. **Indirect-dispatch tax on the AOT core** — biggest perf risk; mitigated by keeping
   final/private/static calls direct + guarded devirt (§3.3).
2. **M2 requires a `fastjavac` toolchain on the target machine** (it shells out to the
   compiler). Acceptable for servers/dev boxes; not for locked-down/freestanding
   targets — those are **M1-only** (runtime detects and reports toolchain absence).
   *Decision (2026-07-25): M2 is in scope alongside M1.* Trust model & cache: §5.1.
3. **Trampoline patching (§3.2)** brings W^X, icache, and cross-thread safepoint
   complexity — scheduled last and opt-in; pointer slots (§3.1) cover most needs without it.
4. **Freestanding/seL4** has no `dlopen`; needs a custom PIC loader/relocator. M1 only.
5. **GC under redefinition** — versioned layouts + per-class field-ref maps are mandatory.

## 10. Recommended first step

**Phase 0 + Phase 1** together: self-contained, preserve today's soundness everywhere
except across the module boundary, prove the frozen native ABI end to end, and produce
the runtime metadata every later phase needs — with **zero interpreter and zero JIT**,
purely native modules linked at runtime.
