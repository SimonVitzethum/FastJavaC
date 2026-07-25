# What LWJGL needs — measured (LWJGL 3.3.3, this machine)

**Context:** LWJGL is Minecraft's rendering layer (OpenGL/GLFW/OpenAL/Vulkan bindings). It is a
**client** concern — Paper (server) needs none of it. This is the analysis for the MC client
path, building on the JNI bridge (NATIVE-STRATEGY.md).

## The big result: LWJGL has NO `JVM_*` wall

Unlike the JDK's `libzip` (which dragged 159 versioned `SUNWprivate_1.1` `JVM_*` upcalls),
`liblwjgl.so` is **self-contained**:

- `NEEDED`: only `libdl`, `libpthread`, `libc`. **Zero** `JVM_*` / `SUNWprivate` symbols.
- It `dlopen`s directly, no fake/real `libjvm.so` required.
- **Proven** (spikes/lwjgl_probe.c): plain `dlopen(liblwjgl.so)` + call
  `Java_org_lwjgl_system_MemoryAccessJNI_getPointerSize` → 8; and
  `Java_org_lwjgl_system_JNI_invokeI(env, cls, &fn)` → calls the function pointer → 42.

So the hard part of the JDK bridge simply does not exist here.

## How LWJGL 3 works (the mechanism)

LWJGL is **pure Java + one self-contained `liblwjgl.so`** (1969 `Java_*` exports) that is a
**hand-rolled FFI**:

- **1605 generic `invoke<shape>(args…, long funcAddr)` dispatchers** in
  `org.lwjgl.system.JNI` — the last `long` is a function pointer; the shape (name + arg types)
  encodes the C signature. `invokePV(f, p)` = call `f(p)` void; `invokeIII(a,b,f)` = `f(a,b)`→int.
  So GL/GLFW calls are: `dlsym` the function once → address; then `JNI.invoke…(address, args)`.
- **Memory**: `org.lwjgl.system.MemoryUtil` uses **`sun.misc.Unsafe`** when available (it is —
  fastjavac already implements it), else `MemoryAccessJNI` (malloc/free/get/put, also in the lib).
- **Loading**: `org.lwjgl.system.linux.DynamicLinkLoader.ndlopen/ndlsym` — LWJGL loads
  `libglfw.so`/`libGL.so`/… and resolves function pointers itself.
- Of the 1605 dispatchers, **446 take arrays/strings** (need a richer JNIEnv); the rest are pure
  primitive+address (a minimal JNIEnv suffices).

## What fastjavac already has that helps

- **`sun.misc.Unsafe`** (off-heap memory) — LWJGL's preferred memory backend. Big win.
- The **JNI bridge** mechanism + `dlopen` + symbol resolver (jrt_jni_*).
- indy/lambda, threads, arrays — all present.

## The concrete work list

1. **`System.load` / `System.loadLibrary` + JNI native registration.** Load the bundled
   `liblwjgl.so` (+ `libglfw`, `libopenal`) and **bind** each Java `native` method to the lib's
   `Java_<class>_<method>` symbol. Runtime feature: a native-method registry that, on a call to
   an unbound `native` method, resolves it in the loaded libs and calls it through the JNI bridge.
   (Generalises the current symbol-named `jrt_jni_ii_aii` to "any native method → its Java_* leaf".)
2. **A general native-call marshaller for the 1605 dispatcher shapes.** Each `invoke…` is a
   static `native` with a fixed primitive/long/float/double descriptor. Calling the lib's symbol
   means marshalling those args per the SysV ABI. **This is the real chunk** — LWJGL is itself an
   FFI, so bridging it needs an FFI. Two options:
   - **libffi** (recommended): implement one descriptor→`ffi_call` path; it covers all 1605
     shapes + every other primitive-signature leaf. Bounded, one-time.
   - Shaped dispatchers generated from the descriptors (no dependency, more code).
3. **Richer JNIEnv** for the 446 array/string dispatchers (`GetPrimitiveArrayCritical`,
   `GetStringUTFChars`, …) — we already have the array-critical pattern; add the string slots.
4. **System GL/GLFW/GPU + a display** — `libGL.so`, X11/Wayland, a GPU driver, for actual
   rendering (LWJGL bundles `libglfw`; `libGL` is the system's). Off-box/headless can't render.
5. **Compile the pure-Java LWJGL closure** closed-world (uses lambdas/threads — present).

## Verdict

LWJGL is **far more tractable than the JDK native layer**: no `JVM_*` wall, a single
self-contained `.so`, and its memory backend is `Unsafe` (already implemented). The bounded work
is: `System.load` + native-method registration + a **libffi-backed invoke bridge** (one path,
covers all 1605 shapes) + the string JNIEnv slots. After that it is a *real GPU/display* problem,
not a VM problem. Order of magnitude: the FFI bridge is the milestone; everything else fastjavac
largely has. And for **Paper (server) none of this is on the path** — LWJGL is client-only.
