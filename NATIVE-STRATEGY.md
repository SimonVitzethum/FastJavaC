# Covering all native calls at once — the library (JNI/`JVM_*`) option

**Question (user):** instead of hand-writing each native leaf (`jrt_io_read`, `jrt_net_connect`,
…), is there a *library* solution that covers **all** native calls at once?

**Short answer:** Yes — reuse the JDK's own shipped native libraries (`libjava.so`,
`libnio.so`, `libnet.so`, `libzip.so`) through a **JNI + `JVM_*` bridge**. This is the classic
approach of alternative JVMs (Avian, JamVM, CACAO). It converts "hundreds of native methods"
into "one finite interface". But that interface has a deep core that is *itself* JVM-internals
work, so the honest recommendation is a **hybrid**, not a pure bridge.

---

## The measured picture (GraalVM 25 on this machine)

| JDK native lib | native methods it implements (`Java_*`) |
|---|---:|
| `libjava.so` | 209 |
| `libnio.so` | 198 |
| `libnet.so` | 32 |
| `libzip.so` | 27 |
| **total** | **466** |

These 466 `Java_*` functions are the *leaf* natives — everything else in the JDK is pure Java
that fastjavac already compiles (or a stub does). So the entire native surface for a headless
server is a **subset of ~466**, not unbounded. That alone is the encouraging news: **the native
problem is finite and already implemented — in these `.so` files.**

**But** `libjava.so` is not free-standing. It imports **157 distinct `JVM_*`** upcalls (the
HotSpot-internal interface, normally provided by `libjvm.so`, which exports 201). To *call* the
shipped leaves you must *provide* those upcalls:

- ~16 **trivial** (`JVM_CurrentTimeMillis`, `JVM_ActiveProcessorCount`, `JVM_ArrayCopy`,
  properties, GC-noops) — a few lines each.
- ~79 **deep** (`JVM_DefineClass`, `JVM_Constant*` constant-pool access, `JVM_CallStackWalk`,
  `JVM_GetStackTraceElements`, module system, threads, monitors, nestmates/records) — these
  require real VM introspection.
- ~62 in between.

Plus the **`JNIEnv`** table itself (~230 function pointers: `GetIntField`, `SetObjectField`,
`NewObjectArray`, `GetPrimitiveArrayCritical`, `Throw`, `CallObjectMethod`, …). Most are
mechanical over fastjavac's object model, but a handful (critical-array pinning, global refs,
method dispatch) touch RC/GC and threading.

## The trade-off, honestly

| | Hand-written leaves (current) | JNI + `JVM_*` bridge |
|---|---|---|
| Work is O( ) | native methods used (~10 done) | ~387 interface fns (230 JNIEnv + 157 JVM_*) |
| Per-item cost | low (simple syscall wrapper on our model) | mixed: ~16 trivial, ~79 deep |
| Coverage after | only what you wrote | **all 466 JDK leaves + any 3rd-party JNI lib** (Netty native transport, LWJGL, libsodium…) |
| Fit to our model | perfect (native to fastjavac) | must emulate JNI handle/refcount/pinning semantics |
| Fragility | none | binds a **specific JDK build** (`JVM_*` is not a stable ABI; version-locked) |
| Overhead | none | JNIEnv indirection per call |

The catch: the ~79 **deep `JVM_*`** are exactly the hard parts of a JVM (class definition,
reflection, constant-pool walking, stack unwinding). Implementing them *is* JVM work — not
cheaper than hand-writing many simple leaves. So a **pure** bridge doesn't make the hard part
disappear; it relocates it into the `JVM_*` table.

## Why it's still powerful — and the key insight

The bridge's real win is **the long tail**: charset tables, `zip`/`Deflater`, `nio` selectors,
crypto, image codecs — hundreds of leaves we'd otherwise hand-port. And uniquely, it also
unlocks **non-JDK JNI libraries** (Netty's epoll transport, etc.) that no amount of
hand-writing reaches. Crucially, **many deep `JVM_*` overlap with services fastjavac already
has**: `JVM_ArrayCopy`→our `jrt_arraycopy`; `JVM_DefineClass`→our JIT class-loader
(`jrt_define_class_jit`); `JVM_GetClass*`/reflection→our FjcClass registry;
`JVM_IHashCode`→`jrt_obj_hashcode`; `JVM_Clone`→our deep-copy vtable slot;
`JVM_MonitorWait`/`Notify`→our monitor runtime. So the `JVM_*` table is largely **thin
adapters onto the runtime we already built**, not new subsystems.

## Recommended path: hybrid, in three tiers

1. **Keep hand-written leaves for the hot, simple, syscall-shaped core** (I/O, sockets, time,
   arraycopy). Already done for `java.io`/`java.net`; ~20–50 leaves total. Fast, controllable,
   model-native, no version lock.
2. **Build a minimal `JNIEnv` + `JVM_*` shim onto the *existing* runtime** — implement the
   ~16 trivial `JVM_*` directly, and route the deep ones to the services fastjavac already has
   (registry, JIT class-loader, RC, monitors). This is the finite unlock and reuses prior work.
3. **`dlopen` the JDK leaf libs (`libzip`/`libnio`/`libnet`/`libjava`) behind that shim** for
   the long tail, binding to the reference JDK on the box (accepting the version lock). Harvest
   the *reachable* leaf set by running the target on the reference GraalVM (roadmap §7) and
   implement/bridge only those.

Net: the native problem is **finite (~466 leaves) and already written**; the bridge makes it
reachable through **~387 interface functions that are mostly thin adapters onto runtime
fastjavac already has**. The deep minority is unavoidable JVM work either way — the bridge just
concentrates it in one well-specified table instead of scattering it across per-class leaves.

## Relation to the JIT-completeness question

Complete Tier-1 JIT (all bytecodes) + this native bridge are the two finite halves:
- **JIT** handles every *pure-Java* method loaded at runtime (mods/plugins) — bytecode is a
  fixed ~200-opcode set.
- **Bridge** handles every *native* leaf those methods bottom out in.
Neither substitutes for the other; together they are "run any jar at runtime". Both are bounded.
