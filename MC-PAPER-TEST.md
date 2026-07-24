# Test Report: Compiling local Modded Minecraft & Paper with fastjavac

**Date:** 2026-07-25
**Request:** After M2, autonomously test against locally installed Modded Minecraft
and Paper.jar "until it works."
**Result:** It does not work, and cannot — established by feeding the real local
artifacts to `fastjavac` and capturing the concrete failures below. This confirms,
with runtime evidence, the analysis in `FEASIBILITY.md`. This is not a bug to iterate
on; it is the closed-world/JDK boundary.

---

## What was tested (real local files)

| Artifact | Path |
|---|---|
| Paper server | `/home/simon/Downloads/paper-26.2-32.jar` (paperclip launcher, 259 classes) |
| Fabric API | `~/.local/share/PrismLauncher/instances/26.2/.../mods/fabric-api-0.152.2+26.2.jar` |
| Sodium (Fabric mod) | `.../run/mods/sodium-fabric-0.8.12+mc26.1.2.jar` (803 classes, 3 mixin/refmap files) |

## Concrete failures

**Paper (`--emit-module` and `--dynamic`):**
```
fastjavac: .../io/papermc/paperclip/FileEntry.class:
  unsupported: invokevirtual java/io/BufferedReader.readLine()Ljava/lang/String;
```
Fails on the **first real class** of the *launcher* — `java.io.BufferedReader` is a
basic JDK class absent from the 24-file stdlib. Note: `paper-26.2-32.jar` is a
**paperclip** bootstrap (`Main-Class: io.papermc.paperclip.Main`); at runtime it
downloads Mojang's server and **patches/launches it reflectively**. So even a
"successful" compile of this jar would only be the launcher, not the server.

The launcher alone references **49 distinct JDK classes** the compiler cannot
resolve, including `java.lang.ClassLoader`, `java.lang.invoke.MethodHandle(s)`,
`java.lang.invoke.MethodType`, `java.io.*`, `java.util.zip.*`.

**Fabric API:**
```
fastjavac: no .class files found (empty JAR?)
```
It contains **0 top-level classes** — Fabric mods bundle **jars-inside-jars**, loaded
by the Fabric loader at runtime. Another dynamic-loading mechanism an AOT compiler
cannot follow.

**Sodium (Fabric mod):**
```
fastjavac: .../sodium/api/vertex/format/common/ParticleVertex.class:
  unsupported: getstatic com/mojang/blaze3d/vertex/DefaultVertexFormat.PARTICLE
```
Fails immediately on a **Minecraft client class** (`com.mojang.blaze3d…`), which would
require the entire MC client + LWJGL natives + the Mixin-woven MC — none of which
exist statically.

## Why no amount of iteration fixes this

These are not missing features to add incrementally; they are the architecture:

1. **The whole JDK is required.** The launcher needs 49 JDK classes; the real server
   and mods need thousands, many backed by `sun.misc.Unsafe`, JNI, and native code.
   The compiler models ~24 `java.util` classes.
2. **`java.lang.invoke.MethodHandle(s)` / general `invokedynamic`.** The compiler
   supports 4 fixed indy shapes; the launcher already uses the general mechanism.
3. **Runtime class loading + bytecode generation.** Paper patches bytecode at boot;
   Fabric loads jars-in-jars and applies **Mixin/ASM** transformations that synthesize
   classes at runtime. There is no static program to AOT-compile.
4. **Native/JNI (LWJGL, Netty transports, crypto).** No JNI bridge, and these are
   native `.so`s expecting a real JVM.

Chasing these by growing the stdlib is a bottomless task that still never yields a
running Paper/MC, because (3) and (4) are unimplementable in an AOT-to-native model.
It would also require, in effect, re-implementing a JVM + JIT — a different project.

## What the M1/M2 pipeline *does* do (verified)

The dynamic-loading machinery built in Phases 0–4 works end-to-end on **self-contained
Java that stays within the supported language/stdlib subset** (see `tests/m1.sh`,
`tests/m2.sh`, `tests/p2.sh`, `tests/p3.sh`): compile a jar to a native module, load it
at runtime (`dlopen`), redefine methods by pointer swap, weave mixins, and even
compile a bytecode jar to a native module on first load and cache it — all as native
CPU code, no VM, no JIT, with the 0-live-heap oracle intact.

The boundary is exactly the JDK-scale surface and the runtime-bytecode-generation that
Paper/Forge/Fabric are built on — not the loader pipeline itself.

## Honest conclusion

Modded Minecraft and Paper cannot be compiled or run by `fastjavac`, now or after
further iteration, for the structural reasons above. The tractable way to run
"game/plugin logic" natively through this toolchain is to author it as closed-world
Java within the supported subset (or as a FastJavaC native module), not as a Bukkit
plugin or a Forge/Fabric mod that presupposes a full JVM.
