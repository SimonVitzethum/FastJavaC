//! fastjavac — Java class files → native binary.
//!
//! Pipeline (DESIGN.md §2, stage 1 of the prioritization §7):
//!   .class → parser → mid-level IR → textual LLVM IR → clang → binary
//!
//! Usage: fastjavac [-o BIN] [--emit-ir] [--emit-llvm] CLASS.class ...

use std::path::PathBuf;
use std::process::{exit, Command};

const RUNTIME_C: &str = include_str!("runtime.c");

fn main() {
    let mut out: Option<PathBuf> = None;
    let mut emit_ir = false;
    let mut emit_llvm = false;
    let mut stats = false;
    let mut no_solver = false;
    let mut freestanding = false;
    let mut threads = false;
    // Phase 1 (M1): --emit-module compiles the input to a loadable native module
    // (.so) instead of an executable; --dynamic builds a host binary able to load
    // such modules at runtime (see DYNAMIC-RUNTIME-PLAN.md §5, PHASE-0-PLAN.md).
    let mut emit_module = false;
    let mut dynamic = false;
    // Phase 3: compile-time mixin weaving. Each --weave Mixin:Target overwrites the
    // target class's methods with the mixin's before codegen (dotted names).
    let mut weaves: Vec<(String, String)> = Vec::new();
    let mut main_override: Option<String> = None;
    let mut raw_inputs: Vec<PathBuf> = Vec::new();

    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "-o" => match args.next() {
                Some(p) => out = Some(PathBuf::from(p)),
                None => die("-o requires an argument"),
            },
            "--main" => match args.next() {
                Some(c) => main_override = Some(c.replace('.', "/")),
                None => die("--main requires a class name"),
            },
            "--emit-ir" => emit_ir = true,
            "--emit-llvm" => emit_llvm = true,
            "--stats" => stats = true,
            "--no-solver" => no_solver = true,
            "--freestanding" => freestanding = true,
            "--threads" => threads = true,
            "--emit-module" => emit_module = true,
            "--dynamic" => dynamic = true,
            "--weave" => match args.next() {
                Some(spec) => match spec.split_once(':') {
                    Some((m, t)) => weaves.push((m.replace('.', "/"), t.replace('.', "/"))),
                    None => die("--weave expects Mixin:Target"),
                },
                None => die("--weave requires a Mixin:Target argument"),
            },
            "-h" | "--help" => {
                println!("Usage: fastjavac [-o BIN] [--main CLASS] [--emit-ir] [--emit-llvm] [--stats] [--no-solver] [--freestanding] [--emit-module] [--dynamic] (CLASS.class | LIB.jar) ...");
                println!("  --emit-module  compile to a loadable native module (.so); entry class needs `static int fjcMain()`");
                println!("  --dynamic      build a host binary that can load such modules at runtime");
                return;
            }
            _ => raw_inputs.push(PathBuf::from(a)),
        }
    }
    if raw_inputs.is_empty() {
        die("no input files (expected .class or .jar)");
    }

    // Unpack JARs (closed-world collection): each .class file becomes an input,
    // the manifest `Main-Class` determines the entry point. The extraction
    // directory must live until the end of compilation.
    let extract_root = std::env::temp_dir().join(format!("fastjavac-jars-{}", std::process::id()));
    let mut inputs: Vec<PathBuf> = Vec::new();
    let mut manifest_main: Option<String> = None;
    for path in &raw_inputs {
        if path.extension().and_then(|e| e.to_str()) == Some("jar") {
            match unpack_jar(path, &extract_root) {
                Ok((classes, main)) => {
                    inputs.extend(classes);
                    if manifest_main.is_none() {
                        manifest_main = main;
                    }
                }
                Err(e) => return die(&format!("{}: {e}", path.display())),
            }
        } else {
            inputs.push(path.clone());
        }
    }
    if inputs.is_empty() {
        die("no .class files found (empty JAR?)");
    }
    let main_class = main_override.or(manifest_main);

    // Two-phase: first register all classes (closed world), then
    // lower — field/method resolution crosses class boundaries.
    let mut classfiles = Vec::new();
    for path in &inputs {
        let data = match std::fs::read(path) {
            Ok(d) => d,
            Err(e) => return die(&format!("{}: {e}", path.display())),
        };
        match fastllvm_classfile::ClassFile::parse(&data) {
            Ok(cf) => classfiles.push((path, cf)),
            Err(e) => return die(&format!("{}: {e}", path.display())),
        }
    }
    // Class data has been read — the JAR extraction directory can go.
    let _ = std::fs::remove_dir_all(&extract_root);

    let mut program = fastllvm_ir::Program::default();
    program.main_class = main_class;
    // Open-world host: disables CHA devirtualization and makes vtables mutable so
    // loaded modules can add subclasses / redefine methods (Phase 2). Modules
    // themselves stay closed-world-optimized over their own classes.
    program.dynamic = dynamic;
    for (path, cf) in &classfiles {
        if let Err(e) = fastllvm_frontend::register_class(cf, &mut program) {
            return die(&format!("{}: {e}", path.display()));
        }
    }
    fastllvm_frontend::register_builtins(&mut program);
    for (path, cf) in &classfiles {
        if let Err(e) = fastllvm_frontend::lower_class(cf, &mut program) {
            return die(&format!("{}: {e}", path.display()));
        }
    }

    // Phase 3: weave mixins over their targets before the solver runs, so the
    // combined class is optimized and lowered as one.
    for (mixin, target) in &weaves {
        let n = fastllvm_solver::weave_mixin(&mut program, mixin, target);
        if n == 0 {
            return die(&format!(
                "--weave {}:{}: no overlapping methods woven (check class/method names)",
                mixin.replace('/', "."),
                target.replace('/', "."),
            ));
        }
    }

    // Provably acyclic → cycle collector is omitted (only if the solver
    // ran; without it, conservatively keep the collector).
    let mut acyclic = false;
    if !no_solver {
        let mut s = fastllvm_solver::run(&mut program);
        // Remove redundant ref self-copies (RC-neutral): javac's `aload`
        // reloads of a loop-invariant reference otherwise produce a
        // retain/release pair per iteration that Rust does not have.
        let _rcopies = fastllvm_solver::elide_redundant_ref_copies(&mut program);
        // Constant-propagate entry-block scalar constants: a `mut n = <const>`
        // divisor becomes a literal → native srem/magic-multiply, not a jrt_lrem
        // call; also feeds constant sizes/bounds to the passes below.
        let _cprop = fastllvm_solver::propagate_const_scalars(&mut program);
        // Fuse long/double comparisons with their 0-test: a `jrt_lcmp` call
        // per loop iteration → native `icmp i64`. Before bounds elision, so
        // its loop-guard detection operates directly on the i64 comparison.
        let _fused = fastllvm_solver::fuse_long_compares(&mut program);
        // Bounds-check elision before pending elision: array accesses proven
        // in-bounds are throw-free, so their pending check is removed along
        // with them.
        let _bounds = fastllvm_solver::elide_bounds(&mut program);
        // Remove dead pending checks BEFORE inlining: there the check still
        // sits in the same block as the (throwing) call; afterwards, inlined
        // bodies move across block boundaries and the block-local analysis
        // would be unsound.
        let _elided = fastllvm_solver::elide_pending_checks(&mut program);
        s.inlined_calls = fastllvm_solver::inline_program(&mut program);
        s.stack_allocated = fastllvm_solver::stack_allocate(&mut program);
        acyclic = s.acyclic;
        if stats {
            eprintln!(
                "solver: {} Klassen instanziiert, {} Funktionen erreichbar ({} entfernt), \
                 {} virtuelle Sites, {} devirtualisiert, {} bikonditional, {} Calls geinlinet, \
                 {} Allokationen auf den Stack, Zyklen-Collector: {}",
                s.instantiated_classes,
                s.reachable_functions,
                s.pruned_functions,
                s.virtual_sites,
                s.devirtualized,
                s.poly_devirtualized,
                s.inlined_calls,
                s.stack_allocated,
                if s.acyclic { "omitted (acyclic)" } else { "required" },
            );
        }
    }

    if emit_ir {
        print!("{program}");
        return;
    }

    let ll = fastllvm_backend::emit(&program);
    if emit_llvm {
        print!("{ll}");
        return;
    }

    let out = out.unwrap_or_else(|| PathBuf::from("a.out"));
    let build_dir = std::env::temp_dir().join(format!("fastjavac-{}", std::process::id()));
    if let Err(e) = std::fs::create_dir_all(&build_dir) {
        return die(&format!("Build-Verzeichnis: {e}"));
    }
    let ll_path = build_dir.join("program.ll");
    let rt_path = build_dir.join("runtime.c");
    if let Err(e) = std::fs::write(&ll_path, &ll).and_then(|_| std::fs::write(&rt_path, RUNTIME_C)) {
        return die(&format!("Schreiben nach {}: {e}", build_dir.display()));
    }

    // --- Phase 1 (M1): native module output ---------------------------------
    // A module is a shared object linked WITHOUT runtime.c: its jrt_* references
    // stay undefined and resolve against the host at dlopen time (so host and
    // module share ONE runtime/heap/collector). It exports:
    //   fjc_module_abi   — the ABI version (host rejects a mismatch),
    //   fjc_module_main  — a wrapper over the entry class's `static int fjcMain()`,
    //   fjc_module_init  — reserved host-callback hook (no-op in v1),
    //   fjc_classes[]/fjc_classes_len — the module's FjcClass registry (dlsym'd).
    if emit_module {
        let entry = match &program.main_class {
            Some(c) => c.clone(),
            None => return die("--emit-module requires an entry class (JAR Main-Class or --main) with `static int fjcMain()`"),
        };
        let has_entry = program
            .class(&entry)
            .map(|c| c.methods.iter().any(|m| m.name == "fjcMain" && m.desc == "()I" && m.is_static))
            .unwrap_or(false);
        if !has_entry {
            return die(&format!("entry class {} has no `public static int fjcMain()`", entry.replace('/', ".")));
        }
        let sym = fastllvm_ir::mangle(&entry, "fjcMain", "()I");
        let shim = format!(
            "#include <stdint.h>\n\
             extern int32_t {sym}(void);\n\
             int32_t fjc_module_main(void) {{ return {sym}(); }}\n\
             const uint32_t fjc_module_abi = {abi}u;\n\
             void fjc_module_init(void *host) {{ (void)host; }}\n",
            abi = fastllvm_ir::FJC_ABI_VERSION,
        );
        let shim_path = build_dir.join("module_shim.c");
        if let Err(e) = std::fs::write(&shim_path, &shim) {
            return die(&format!("Schreiben nach {}: {e}", build_dir.display()));
        }
        let mut cmd = Command::new("clang");
        cmd.arg("-O2").arg("-shared").arg("-fPIC");
        cmd.arg(&ll_path).arg(&shim_path);
        // Undefined jrt_* symbols are resolved at load against the host.
        cmd.args(["-ffunction-sections", "-fdata-sections"]);
        if threads {
            cmd.args(["-DFASTLLVM_THREADS", "-pthread"]);
        }
        let status = cmd.arg("-o").arg(&out).status();
        match status {
            Ok(s) if s.success() => {
                let _ = std::fs::remove_dir_all(&build_dir);
                return;
            }
            Ok(s) => return die(&format!("clang (module) schlug fehl ({s}); Zwischendateien in {}", build_dir.display())),
            Err(e) => return die(&format!("clang not runnable: {e}")),
        }
    }

    // --dynamic host: force the cycle collector on (open world → the acyclicity
    // proof no longer holds once modules load), export jrt_* to loaded modules
    // (-rdynamic), link libdl, and keep the full runtime (no --gc-sections, so a
    // module can resolve helpers the host itself never calls).
    let acyclic = acyclic && !dynamic;

    // Freestanding (seL4): no libc, no startup. The result is a relocatable
    // object (`clang -r`) that the target environment links together with its
    // own _start and the weak hooks (jrt_debug_putchar/jrt_platform_halt).
    let mut cmd = Command::new("clang");
    cmd.arg("-O2").arg(&ll_path).arg(&rt_path);
    // Phase 2: each function/data object in its own section, strip unused
    // ones at link time — so e.g. `Hello` pulls in only the jrt_ functions
    // actually called instead of the whole runtime.
    cmd.args(["-ffunction-sections", "-fdata-sections"]);
    // LTO: the generated program and runtime.c are compiled as separate
    // objects — without LTO, clang does NOT inline the runtime helpers
    // (jrt_iaload, jrt_pending_set, jrt_lcmp …) across the file boundary into
    // the hot loops. LTO enables exactly this cross-file inlining.
    if !freestanding {
        cmd.arg("-flto");
    }
    if !freestanding {
        // --dynamic keeps the whole runtime (a loaded module may resolve helpers
        // the host never calls itself) and exports jrt_* + libdl for dlopen.
        if dynamic {
            cmd.args(["-rdynamic", "-ldl", "-DFASTLLVM_DYNAMIC"]);
        } else {
            cmd.arg("-Wl,--gc-sections");
        }
        // Closed-world AOT on the target machine: compile for the native ISA
        // (AVX2/BMI etc.), as one builds optimized C++ with `-O3 -march=native`.
        // Vectorizes hot loops (arithmetic 2.4× faster than the SSE baseline
        // build). Freestanding/cross targets remain excluded.
        cmd.arg("-march=native");
    }
    if threads {
        cmd.args(["-DFASTLLVM_THREADS", "-pthread"]);
    }
    if acyclic {
        // Phase 1: no type can form cycles → cycle collector is not linked in,
        // retain/release become color-/buffer-free.
        cmd.arg("-DFASTLLVM_NO_CYCLES");
    }
    if freestanding {
        cmd.args([
            "-r",
            "-nostdlib",
            "-ffreestanding",
            "-fno-stack-protector",
            "-DFASTLLVM_FREESTANDING",
        ]);
    }
    let status = cmd.arg("-o").arg(&out).status();
    match status {
        Ok(s) if s.success() => {
            let _ = std::fs::remove_dir_all(&build_dir);
        }
        Ok(s) => die(&format!("clang schlug fehl ({s}); Zwischendateien in {}", build_dir.display())),
        Err(e) => die(&format!("clang not runnable: {e}")),
    }
}

fn die(msg: &str) {
    eprintln!("fastjavac: {msg}");
    exit(1);
}

/// Unpacks a JAR (ZIP) into `<root>/<jar-stem>/` and returns the list of
/// contained `.class` files as well as the `Main-Class` from the manifest.
/// Uses `unzip` or the JDK `jar` (both present with a Java toolchain);
/// this keeps the compiler dependency-free and the runtime untouched.
fn unpack_jar(jar: &std::path::Path, root: &std::path::Path) -> std::io::Result<(Vec<PathBuf>, Option<String>)> {
    let stem = jar.file_stem().and_then(|s| s.to_str()).unwrap_or("jar");
    let dir = root.join(stem);
    std::fs::create_dir_all(&dir)?;
    let jar_abs = std::fs::canonicalize(jar)?;
    // Prefers `unzip`, otherwise `jar xf` (executed in the target directory).
    let ok = Command::new("unzip")
        .args(["-oq"])
        .arg(&jar_abs)
        .arg("-d")
        .arg(&dir)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
        || Command::new("jar")
            .arg("xf")
            .arg(&jar_abs)
            .current_dir(&dir)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
    if !ok {
        return Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            "unpacking failed (neither `unzip` nor `jar` available)",
        ));
    }
    // Collect .class files recursively.
    let mut classes = Vec::new();
    collect_classes(&dir, &mut classes)?;
    // Main-Class from the manifest (dotted → internal with '/').
    let manifest = dir.join("META-INF").join("MANIFEST.MF");
    let main = std::fs::read_to_string(&manifest).ok().and_then(|txt| {
        txt.lines()
            .find_map(|l| l.strip_prefix("Main-Class:"))
            .map(|v| v.trim().replace('.', "/"))
    });
    Ok((classes, main))
}

fn collect_classes(dir: &std::path::Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let p = entry?.path();
        if p.is_dir() {
            collect_classes(&p, out)?;
        } else if p.extension().and_then(|e| e.to_str()) == Some("class") {
            out.push(p);
        }
    }
    Ok(())
}
