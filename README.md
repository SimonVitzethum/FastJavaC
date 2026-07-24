# FastJavaC — Java → safe native binary compiler

An ahead-of-time compiler that turns Java bytecode (`.class` / `.jar`) into a
**native binary** with **automatic, sound memory management** — no GC pauses, no
`unsafe`. This is the Java-AOT pipeline extracted from the FastLLVM/Vire monorepo:
the `fastjavac` driver plus the five libraries it depends on. It contains **no**
Vire language, GPU/Vulkan, or CSolver code — just the Java → safe-binary path.

## What it does

Closed-world (all classes given up front), so the whole program is known and the
soundness analyses can be exact:

- **`crates/classfile`** — parses `.class` / `.jar` (constant pool, methods, attributes).
- **`crates/frontend`** — Java bytecode → mid-level SSA IR.
- **`crates/ir`** — the shared IR (lowering target).
- **`crates/solver`** — the safety/optimization analyses: **devirtualization**,
  **escape analysis** (stack-allocate non-escaping objects), **reference-counting
  elision** (drop redundant retain/release on the provably-stable set), and
  **array-bounds-check elision**.
- **`crates/backend`** — IR → LLVM IR text, linked against the C runtime.
- **`crates/driver`** — the `fastjavac` binary and `runtime.c` (RC + cycle collector,
  arrays, strings, exceptions, threads). `runtime.c` is embedded into the binary and
  compiled together with the generated program (thin LTO).

Memory management is **invisible and automatic**: reference counting with a cycle
collector, but the solver proves away most RC ops and stack-allocates what doesn't
escape. Correctness is checked by a **0-live heap oracle** — every test asserts the
heap balances to zero live objects at exit.

## Build

No external crates — pure Rust `std`. Requires a recent `rustc`/`cargo`, plus
`clang`/LLVM and a JDK (`javac`, `jar`) for the tests.

```sh
cargo build --release        # produces target/release/fastjavac
```

## Use

```sh
javac -d out Hello.java
fastjavac -o hello out/Hello.class     # closed-world: pass every class the program uses
./hello
```

Flags: `--threads` (real pthreads + atomic RC + monitors), `--freestanding`
(libc-free object for bare-metal/seL4, linked with `sel4/bringup.c`),
`-o <out>` (output path). Set `FASTLLVM_HEAPSTATS=1` at run time to print the
heap balance.

## Tests

The regression suite compiles each example with `javac` + `fastjavac`, runs it,
and checks both the exit code and the 0-live heap balance:

```sh
cargo build                  # debug fastjavac (the suite uses target/debug)
sh tests/run.sh
```

`examples/` holds the Java test programs, `stdlib/` a minimal `java.util` used by
the collections/streams tests, `benchmarks/` a few numeric benchmarks, and
`sel4/bringup.c` the bare-metal shim for the freestanding test.

## Licence

GPL-3.0-or-later (see `LICENSE`). Extracted from the FastLLVM project.
