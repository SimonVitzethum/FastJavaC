# Phase 0 — Implementation Plan: ABI Freeze & Runtime Class Metadata

**Date:** 2026-07-25
**Status:** Implementation plan — no code yet.
**Prereq for:** all of M1 (native plugin ABI) and M2 (compile-on-load). See
`DYNAMIC-RUNTIME-PLAN.md` §4, §8.

**Goal of Phase 0:** make the AOT core's class model **self-describing and queryable at
runtime, under a frozen versioned ABI** — without yet loading anything dynamically. At
the end, a normal AOT binary can, at runtime, look up any of its own classes by name and
read its layout, vtable, fields, and methods. This is the substrate every later phase
builds on; it must ship with the 0-live-heap oracle unchanged.

---

## 1. What already exists (and where)

The information a runtime descriptor needs is **already computed** by the backend and
emitted as LLVM globals — but it is `internal`, name-mangled, unversioned, and not
reachable by class name at runtime. Concretely:

| Metadata | Emitted today as | Location |
|---|---|---|
| Object header | `{ i64 refcount(packed flags+count), ptr vtable, <fields…> }` | `crates/driver/src/runtime.c:8`; header words = 2 (`HEADER_SLOTS = 2`, `VTABLE_WORD = 1` in `crates/backend/src/lib.rs:262-264`) |
| Vtable | `@vt.<class> = internal … [N x ptr]`, slots: 0 drop, 1 trace, 2 typedesc, 3 deep-copy, 4+ global interface slots, then class virtual methods | `crates/backend/src/lib.rs:265-268`, `:873`, `vtable_slots`/`vtable_index` `:396-426` |
| Type descriptor (for `instanceof`/`checkcast`) | `@td.<class> = internal constant { ptr super, ptr name, ptr … interfaces }` — a walkable superclass chain ending at null | `crates/backend/src/lib.rs:720-761`; consumed by `jrt_instanceof`/`jrt_checkcast` `:2828-2838` |
| Static fields | `@sf.<owner>.<field> = internal global …` | `crates/backend/src/lib.rs:379-382`, `:783` |
| Method symbols | `J_<class>_<name>_<desc>` (mangling shared across crates) | `crates/ir/src/lib.rs:556-566` |
| Field layout | flattened, superclass-first; field i at GEP `i + HEADER_SLOTS` | `crates/backend/src/lib.rs:355-376` |

**Key insight:** Phase 0 is *not* inventing metadata — it is **promoting the existing
`@td.*` type descriptor into a full, versioned, name-addressable `FjcClass` record**,
extending it with fields/methods/layout, and adding a registry + lookup API.

### 1.1 Cleanups to do first (correctness of the record depends on them)
- **Stale header comment.** `crates/backend/src/lib.rs:257-262` documents a 3-word
  header (refcount / rcflags / vtable) but the code and `runtime.c:8` use a **2-word**
  header (packed refcount, vtable). Fix the comment; the `FjcClass.instance_size` and
  field offsets must be derived from the *actual* 2-word header. **Verify empirically**
  before freezing (emit + inspect one struct) — this is load-bearing for the ABI.

## 2. The frozen ABI (`FJC_ABI_VERSION`)

Introduce a single versioned contract, shared by the compiler (Rust) and the runtime
(C), that pins everything a separately-compiled module or a runtime query may rely on:

1. **Object header layout** — word 0 packed refcount+flags, word 1 vtable ptr; fields
   follow. (Documented, not changed.)
2. **Vtable slot ordering** — 0 drop, 1 trace, 2 typedesc, 3 deep-copy, 4 … global
   interface slots, then class virtual methods. **This ordering becomes contractual.**
3. **`FjcClass` / `FjcMethod` / `FjcField` struct layouts** (§3).
4. **`jrt_*` runtime entry points** a descriptor references (drop/trace/copy signatures).
5. **Name mangling** (`crates/ir` `mangle`).

Representation: a single source of truth. Define the version as one constant in **both**
a new `crates/ir` item (`pub const FJC_ABI_VERSION: u32`) and a generated C header (or a
`#define` block prepended to `runtime.c` by the driver, mirroring how `RUNTIME_C` is
already `include_str!`-embedded). A build-time assert checks the two agree. **Bumping the
version is a deliberate, documented act** (any layout/ordering change bumps it).

## 3. The runtime record: `FjcClass`

A C-ABI struct emitted (as an LLVM global) for **every** class in the program, reachable
from a registry by internal name. Superset of today's `@td.*`.

```c
/* All pointers are absolute (relocated by the linker/loader). Strings are NUL-terminated
 * UTF-8. Layout is frozen under FJC_ABI_VERSION. */
typedef struct FjcClass {
    uint32_t   abi_version;      /* == FJC_ABI_VERSION; checked on registration */
    uint32_t   flags;            /* bit0 interface, bit1 abstract, bit2 has_clinit, … */
    const char *name;            /* internal name, e.g. "pkg/Foo" (this is the @td name ptr) */
    const struct FjcClass *super;/* null for Object/base (the existing @td super chain) */
    const void *vtable;          /* == @vt.<class>; slot ordering per §2.2 */
    uint32_t   vtable_len;       /* number of ptr slots in vtable */
    uint32_t   instance_size;    /* bytes incl. 2-word header; from flatten_fields + header */
    uint32_t   n_ifaces;  const struct FjcClass *const *ifaces;   /* direct interfaces */
    uint32_t   n_fields;  const struct FjcField  *fields;         /* declared instance fields */
    uint32_t   n_methods; const struct FjcMethod *methods;        /* declared methods */
    /* GC support for dynamically loaded instances (used from Phase 2 on; emitted now): */
    uint32_t   n_ref_offsets; const uint32_t *ref_offsets;        /* byte offsets of ref fields */
} FjcClass;

typedef struct FjcField {
    const char *name; const char *desc; /* JVM descriptor, e.g. "I", "Lpkg/Bar;" */
    uint32_t offset;                    /* byte offset from object base */
    uint8_t  is_ref;                    /* participates in tracing */
} FjcField;

typedef struct FjcMethod {
    const char *name; const char *desc;
    int32_t  vtable_index;   /* -1 if non-virtual (static/<init>/final-direct) */
    const void *code;        /* native entry (== the J_… symbol) or null if abstract */
    uint32_t flags;          /* static, abstract, final, … */
} FjcMethod;
```

Notes:
- `name`, `super`, `ifaces` reuse exactly the pointers the current `@td.*` already emits —
  so `jrt_instanceof`/`jrt_checkcast` can migrate to walking `FjcClass.super` with **no
  behavior change** (a good early correctness anchor).
- `ref_offsets` is derived from `ref_field_slots` (`crates/backend/src/lib.rs:386-393`)
  turned into byte offsets — it lets the collector trace instances whose class was loaded
  dynamically. Emitted in Phase 0, first *consumed* in Phase 2.
- `code`/`vtable_index` make method redefinition (Phase 2) a pointer store.

## 4. The class registry + lookup API

A name→`FjcClass*` map, populated at startup from the emitted descriptors.

- **Emission:** the backend emits a static array `@fjc_classes = [ N x ptr ]` (all
  `FjcClass*`) plus `@fjc_classes_len`. No hashing at build time — keep it a flat table.
- **Runtime (in `fjrt`/`runtime.c`):**
  ```c
  const FjcClass *jrt_class_by_name(const char *internal_name);   /* linear or hashed lookup */
  const FjcMethod *jrt_method(const FjcClass*, const char *name, const char *desc);
  int32_t jrt_vtable_index(const FjcClass*, const char *name, const char *desc);
  ```
  Phase 0 builds a startup index (hash map over the flat table) so lookups are O(1).
  The **dynamic** registry (writable, for loaded modules) is Phase 1/2; Phase 0 ships the
  **static, read-only** registry only.
- **Startup hook:** register descriptors before `java_main` (alongside the existing
  clinit chain in `emit_clinit_chain`, `crates/backend/src/lib.rs:1232`).

## 5. Concrete change list (by file)

| File | Change |
|---|---|
| `crates/ir/src/lib.rs` | Add `pub const FJC_ABI_VERSION: u32`. Optionally expose helpers for descriptor field ordering so backend/runtime agree. |
| `crates/backend/src/lib.rs` | Fix header comment (§1.1). Emit per class: `FjcField[]`, `FjcMethod[]`, `ref_offsets[]`, and the `FjcClass` global (extending the existing `@td.*` emission at `:720-761`). Emit `@fjc_classes` table. Compute `instance_size` from `flatten_fields` + 2-word header; `ref_offsets` from `ref_field_slots`. Make vtable slot order contractual (comment + version). |
| `crates/driver/src/runtime.c` | Define the `Fjc*` structs (guarded by `FJC_ABI_VERSION`). Add `jrt_class_by_name` / `jrt_method` / `jrt_vtable_index` + the startup index build. Migrate `jrt_instanceof`/`jrt_checkcast` to walk `FjcClass.super` (behavior-preserving). |
| `crates/driver/src/main.rs` | Prepend/assert `FJC_ABI_VERSION` into the compiled `runtime.c` unit so Rust and C share one value. |
| `tests/` | New test (§6). |

Nothing in `crates/frontend` or `crates/solver` changes in Phase 0 (the class model they
produce is already sufficient; open-world frontend mode is Phase 2).

## 6. Test plan (must keep the 0-live-heap oracle green)

1. **Introspection test.** A small Java program whose `main` calls a new intrinsic
   (e.g. `Runtime.fjcClassName(obj)` mapped to `jrt_class_by_name`/descriptor read) to
   print its own class name, field count, and `instance_size`; assert expected values.
   *Reuses the existing static-reflection intrinsic plumbing in the frontend.*
2. **Behavior-preservation.** Run the full `tests/run.sh` suite unchanged: migrating
   `instanceof`/`checkcast` to `FjcClass.super` must not change any result, and every
   example must still balance to 0 live objects.
3. **ABI-version assert.** A compile-time check that the Rust and C `FJC_ABI_VERSION`
   agree; a deliberate mismatch fails the build.
4. **Layout golden test.** Emit `--emit-llvm` for one class; snapshot the `FjcClass`
   global so accidental layout changes are caught (and force a version bump).

## 7. Work order (small, independently reviewable steps)

1. Header-comment fix + empirical layout verification (§1.1). *(tiny, unblocks trust)*
2. `FJC_ABI_VERSION` in `crates/ir` + C mirror + assert (§2, §5).
3. Emit `FjcField[]` / `FjcMethod[]` / `ref_offsets[]` per class (backend).
4. Emit the `FjcClass` global + `@fjc_classes` table (backend), extending `@td.*`.
5. `Fjc*` structs + registry + lookup API in `runtime.c`; startup index build.
6. Migrate `instanceof`/`checkcast` to `FjcClass.super` (behavior-preserving).
7. Introspection intrinsic + tests (§6).

Each step compiles and passes `tests/run.sh` on its own.

## 8. Explicitly NOT in Phase 0

- No dynamic loading, no `dlopen`, no writable/dynamic registry (Phase 1+).
- No `--emit-module` / `.so` output (Phase 1).
- No open-world frontend, no interpreter, no JIT (never; and Phase 2+ for open-world).
- No method redefinition yet — but the `FjcMethod.code` slot is emitted so Phase 2 is a
  pure addition, not a re-layout (which would cost an ABI bump).

## 9. Risks specific to Phase 0

- **Freezing the ABI too early.** Mitigation: derive every offset/size empirically from
  the real emission (§1.1), and land the golden layout test (§6.4) *before* declaring the
  version stable.
- **Binary-size / startup cost** of descriptors for large programs. Mitigation: emit
  descriptors in their own sections so `--gc-sections` can drop unreferenced ones in
  pure-AOT builds (the driver already passes `-ffunction-sections -fdata-sections
  -Wl,--gc-sections`, `crates/driver/src/main.rs:185`, `:194`); only `--dynamic` builds
  force-keep the full table.
- **Two sources of truth for the ABI** (Rust + C) drifting. Mitigation: the §6.3
  compile-time assert.
