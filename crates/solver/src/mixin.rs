//! Compile-/load-time mixin weaving (Phase 3, DYNAMIC-RUNTIME-PLAN.md §5).
//!
//! A mixin overwrites methods of a target class before native codegen: for each
//! method the mixin class defines that the target also declares (same name+desc),
//! the target's IR body is replaced by the mixin's, and references to the mixin
//! class inside the woven body are rewritten to the target class (so field/`new`/
//! virtual-call sites resolve against the target's layout — the standard mixin
//! `@Shadow` contract). This produces one combined class that is compiled to native
//! code like any other — no VM, no runtime bytecode manipulation.
//!
//! Limitations (documented): `@Overwrite` semantics only (the woven body does not
//! call the original); the woven body must not `invokespecial`/call a mixin-private
//! or `super` method (those lower to direct calls by mangled symbol, which are not
//! rewritten). Injection (call-original-plus-extra) is a later refinement.

use fastllvm_ir::*;

/// Weave `mixin`'s methods over `target`. Returns the number of methods woven.
pub fn weave_mixin(program: &mut Program, mixin: &str, target: &str) -> usize {
    let mixin_methods: Vec<(String, String)> = match program.class(mixin) {
        Some(c) => c
            .methods
            .iter()
            .filter(|m| m.has_body && m.is_virtual())
            .map(|m| (m.name.clone(), m.desc.clone()))
            .collect(),
        None => return 0,
    };

    let mut woven = 0;
    for (name, desc) in mixin_methods {
        let target_sym = mangle(target, &name, &desc);
        let mixin_sym = mangle(mixin, &name, &desc);
        let mi = program.functions.iter().position(|f| f.name == mixin_sym);
        let ti = program.functions.iter().position(|f| f.name == target_sym);
        let (Some(mi), Some(ti)) = (mi, ti) else { continue };

        // Take a clone of the mixin body, rewrite mixin-class refs to the target,
        // and graft it into the target function (keeping the target's identity).
        let mut body = program.functions[mi].clone();
        rewrite_class_refs(&mut body, mixin, target);
        let t = &mut program.functions[ti];
        t.locals = body.locals;
        t.blocks = body.blocks;
        // params / ret / name / receiver_nonnull stay the target's (same signature).
        woven += 1;
    }
    woven
}

/// Rewrite every `class == from` reference inside `f` to `to`.
fn rewrite_class_refs(f: &mut Function, from: &str, to: &str) {
    let fix = |c: &mut String| {
        if c == from {
            *c = to.to_string();
        }
    };
    for bb in &mut f.blocks {
        for st in &mut bb.statements {
            match st {
                Statement::GetField { class, .. }
                | Statement::PutField { class, .. }
                | Statement::GetStatic { class, .. }
                | Statement::PutStatic { class, .. }
                | Statement::New { class, .. }
                | Statement::StackNew { class, .. }
                | Statement::CheckCast { class, .. }
                | Statement::InstanceOf { class, .. }
                | Statement::InstanceOfPending { class, .. }
                | Statement::CallVirtual { class, .. } => fix(class),
                _ => {}
            }
        }
    }
}
