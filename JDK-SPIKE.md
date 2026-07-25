# JDK-Compile Spike (Roadmap Milestone 2) — Findings

**Date:** 2026-07-25
**Goal:** compile real OpenJDK `java.base` classes with dependencies and run a JDK-heavy
program — the biggest lever toward Paper. This documents what the attempt revealed.
**Source:** GraalVM 25 `java.base` (7,357 classes), fed to `fastjavac`.

---

## 1. The decisive finding: you cannot compile a *small* JDK slice

Real JDK classes have exploding transitive closures. Compiling `java.util.Objects` alone:
- wall 1: `new java.lang.AssertionError` — missing class → provide it;
- wall 2 (after providing it): `invokeinterface java.util.Comparator.compare` — missing →
  and `Comparator`'s default methods + `java.util.function.*` pull in **lambdas
  (invokedynamic)**, which pull in more, and so on.

The closed-world compiler needs the **entire** transitive closure present, and for any
real JDK class that closure spans much of `java.util` + `java.lang` + `java.lang.invoke`.
**Conclusion: the JDK must be compiled as one whole closed world, not incrementally.**

## 2. With the whole `java.base` as the closed world, the walls become *real features*

Feeding all 7,357 `java.base` classes at once (dependencies satisfied), the first
non-dependency wall is:
```
sun/util/PropertyResourceBundleCharset.class:
  unsupported: Class.getCanonicalName()  (reflection subset: forName, getName, newInstance)
```
i.e. a **real feature gap**, not a missing class. So once the closure is whole, the
residual work is exactly the enumerable feature backlog:

| Residual wall | What it needs |
|---|---|
| **Reflection generality** | `Class.getCanonicalName`/`getGenericInterfaces`/… beyond the constant-arg `forName/getName/newInstance` subset |
| **Full `invokedynamic`** | today only 4 shapes (string-concat, lambda, record, pattern-switch); the JDK uses the general bootstrap mechanism + `MethodHandles`/`VarHandle` pervasively (every `java.util.function` lambda) |
| **The native layer** | native methods have no bytecode → must be implemented (§3) |
| **Core-model completeness** | `fastjavac` models only ~4 exceptions (`Throwable/Exception/RuntimeException/MatchException`) and `String`/`StringBuilder` with intrinsic gaps (e.g. `StringBuilder.append(F)`); the real hierarchy (`Error`, `AssertionError`, …) and full String/StringBuilder are needed |
| **Parser robustness** | huge constants trip the Modified-UTF-8 reader (`sun/nio/cs/GB18030`, charset tables) |

## 3. The native-method backlog (measured, concrete)

Native methods per core package (must be hand-implemented — the real work of §3):

| Package | native methods | classes |
|---|---:|---:|
| `java.lang` | 116 | 308 |
| `java.io` | 48 | 155 |
| `java.nio` | 5 | 89 |
| `jdk.internal.misc` (Unsafe etc.) | 90 | 34 |
| `sun.nio.ch` (channels/selectors) | 133 | 134 |
| `java.util` | **2** | 485 |

**Reading:** `java.util` is ~pure Java (2 native / 485) — it compiles once its foundation
exists. The native surface is concentrated in `java.lang` (Object/System/Thread/Class),
`java.io`, `sun.nio.ch` (the NIO/Netty path), and `jdk.internal.misc.Unsafe`. A headless
server's *reachable* native set is a subset of these — on the order of **a few hundred**
methods (arraycopy, hashCode/clone, currentTimeMillis, defineClass, file/socket I/O,
selectors, Unsafe memory/CAS).

## 4. Consequence: Milestone 2 is *gated* on Milestones 3 & the native layer

Because the closure of any real JDK class pulls in lambda-using and native-backed classes,
"compile the JDK" cannot proceed before:
1. **Full `invokedynamic` + `MethodHandles`** (roadmap §4 / milestone 3) — a hard
   prerequisite (every `java.util.function` lambda needs it), and self-contained (no
   native layer required to build it).
2. **The native layer** (roadmap §3) — the few-hundred-method backlog above, implemented
   against `fastjavac`'s object model + real syscalls.
3. **A complete core model** — extend the modeled `java.lang` (full exception hierarchy,
   complete `String`/`StringBuilder`) or compile real `java.lang` + its native layer.
4. **Reflection generality** + **parser robustness on huge constants** (both smaller).

## 5. Recommended next concrete step

**Do full `invokedynamic`/`MethodHandles` next (milestone 3).** It is the gating
prerequisite for compiling the JDK (lambdas are everywhere), it is self-contained (buildable
without the native layer), and it also unblocks lambda-heavy application/mod code. After it,
the native layer (§3) can be built to the *reachable* set — harvested precisely by running
the target on the reference GraalVM (roadmap §7) and recording the native methods it calls.

Attempting to brute-force the native layer or reflection first would stall, because without
indy the lambda-using JDK classes don't compile at all — so you could never link a whole
`java.base`. Indy is the unlock.

## 6. Honest scale

Even with indy + the native layer + a complete core, actually booting Paper is the
downstream ladder (Netty/NIO → boot to console → plugins → mods) on top of a compiled JDK —
collectively a multi-person-year, JVM-scale effort. This spike's value is proving the
*shape*: the JDK is compilable as one closed world, the residual backlog is finite and
enumerable, and **invokedynamic is the correct next unlock**, not the native layer.
