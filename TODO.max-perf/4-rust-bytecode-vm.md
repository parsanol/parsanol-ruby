# 4. Rust bytecode VM for the portable grammar (P1, strategic, multi-PR)

## Why

The portable parser is a recursive tree-walker: every atom attempt is
a function call, an enum match, and per-atom bookkeeping. The profile
after full memoization shows ~99% of parse time in that recursion
overhead — the grammar is interpreted, not compiled. The 2022–2026
literature (XGrammar-2 JIT, Pest codegen, CPython's generated PEG
parser) and our own Ruby VM (TODO.perf/6) converge on compiling the
grammar to a flat program with explicit stacks. Doing this in Rust is
the strategic endgame: sub-second giants, and it becomes the single
execution engine behind MRI ext, FFI, and wasm.

## Design

### Compilation (once per grammar, cached with the handle)

- Input: optimized `Grammar` atoms. Output: flat stride-4 integer
  program (opcode + operands) plus static pools (string table, regex
  table, name table).
- Opcodes (mirroring the Ruby VM's proven set):
  `LIT, RE_ANY, SEQ_PUSH, BT_PUSH, CHOICE, BYTE_DISPATCH, REP, MAYBE,
  CAPTURE, NAMED, ENTITY_CALL, ENTITY_RET, IGNORE, LOOK_AHEAD,
  LOOK_NOT, CUT, SCOPE, FAIL, ACCEPT`.
- Entities compile to subroutines; shared atoms dedupe.
- `BYTE_DISPATCH` bakes in the TODO.max-perf/1 tables at compile time.

### Execution (explicit stacks, no recursion)

- Operand stack for values; backtrack stack of (pc, pos, arity,
  marks) restored on failure.
- Values are arena indices (AstNode) — construction rules must be
  BYTE-IDENTICAL to the tree-walker's per-kind folding (sequence
  nil-skipping, alternative passthrough, maybe-tag semantics,
  repeated-sibling-capture guard from parsanol-rs#66). The Ruby VM
  already encodes these rules; port them, do not reinvent.
- Memoization: (pos, call-site) table reusing DenseCache's recycling
  cap; successes and failures both.

### Gating and fallback

- Compile-time capability check per grammar (same atom-kinds audit as
  the Ruby side's `UnsupportedGrammar` gate): grammars using atoms
  the VM cannot express keep the tree-walker engine. No per-parse
  fallback — engine selection happens once at registration.
- Tree-walker stays as the reference implementation and differential
  oracle.

### Phases

1. Compiler + core opcodes (LIT/RE/SEQ/CHOICE/REP/MAYBE/CAPTURE/
   NAMED/ENTITY/IGNORE) with value-parity differential vs tree-walker
   on the full rs corpus.
2. BYTE_DISPATCH + memoization integration.
3. Lookahead/Cut/Scope/Dynamic semantics; wasm parity.
4. Flip default engine; keep tree-walker behind a feature flag as the
   oracle; retire interpreted paths from the hot pipeline.

### Acceptance gates

- Differential: identical ASTs and failure diagnostics vs tree-walker
  on rs tests, parsanol-ruby suites, and the 140-file SRL corpus.
- Perf: ≥3x on giant EXPRESS schemas end-to-end parse stage; no
  regression on small inputs.

## Defect inventory (found by the new differential gate, 2026-09-18)

`parsanol/src/portable/bytecode/packrat_differential.rs` runs both
engines over a grammar battery and compares success/failure, end_pos,
and the materialized tree. Current failing classes (tests carried as
`#[ignore = "..."]` so the inventory stays executable):

1. **Entity compilation never emitted bodies or `Return`** (FIXED this
   round): `compile_entity` emitted a CALL placeholder and relied on
   the target being compiled elsewhere — reference-based grammars
   (every real grammar) failed with `UnresolvedReference`. Fixed with
   a post-root subroutine queue; bodies compile after the main program
   (a call's return address is the following instruction, so inline
   placement corrupts returns) and each ends with `Return`.
2. **Backtrack-frame protocol conflates return frames and choice
   frames**: `Return` pops the backtrack stack unconditionally, so a
   `Choice` frame left on the stack inside a subroutine body gets
   popped as a return → re-execution loop
   (`RecursionLimitExceeded` on repetition-of-entity; valid inputs
   fail after optional/choice-in-sequence). Needs frame-kind
   discrimination (LPeg-style Commit/Return split).
3. **Value construction diverges from the tree-walker**: no
   `:sequence`/`:repetition` tagged-array envelopes, capture hashes
   built eagerly instead of the tree-walker's `CaptureState`
   (generational scope folding) protocol, `RepetitionTag::Maybe` is
   dropped by the compiler (`{ atom, min, max, .. }` swallows `tag`)
   so `.maybe` yields arrays instead of nil-or-value.
4. **No deepest-failure diagnostics bridge**: the VM's `ErrorTracker`
   is discarded by `parse_with_vm`; the FFI error path needs the same
   (position, expected-labels) contract as
   `PortableParser::failure_diagnostics`.

Phase 1 must clear all four before any wiring.

## Status

Design complete; phase-1 defects inventoried and gated by the
differential harness; implementation scheduled as phased PRs (P1).
