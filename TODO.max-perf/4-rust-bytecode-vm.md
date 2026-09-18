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

## Phase 1 DONE (2026-09-18, parsanol-rs#75)

All four defect classes cleared; the five differential tests are live
and green (byte-identical trees, end_pos, and success/failure vs the
tree-walker):

1. Frame protocol rebuilt: LPeg-interleaved ordered choice (each Choice
   before its own branch), backtrack frames carry value/register/
   capture heights and a kind (Choice/Return/Predicate/Mark), unwinding
   truncates to the popped frame and skips non-choice frames instead of
   resuming callers mid-sequence, PartialCommit jumps to the loop body
   and updates heights so completed iterations survive backtracking.
2. Value model rebuilt: terminals push InputRef values; BuildSeq/
   BuildRep/BuildHash/ToNil/PushNil/CapMark/RecordCapture/ScopeEnd
   reproduce the tree-walker's raw tagged envelopes, Maybe flattening,
   Named hashes, deferred span captures, and scope discard.
3. Maybe tag honored end-to-end (RepetitionTag flows through
   compilation).
4. Regex-at-EOF parity with parse_re; empty Str pushes a zero-width
   value.

Measured (benches/large-input.rs, program compiled once): 64 KB
2.76x (1.93 GiB/s), 64 KB fail-at-end 1.55x; 2 KB -16% (per-parse VM
setup) — engine selection stays a registration-time concern.

Dynamic/Custom atoms are gated out with UnsupportedFeature (phase 3);
legacy dynamic parity tests assert the gate.

## Phase 2 DONE (2026-09-18, parsanol-rs#76 → 0.6.1)

Production parses run on the precompiled program behind deterministic
gates (no Ruby involvement):

- **Compile-once at registration**, on a dedicated large-stack thread
  (compiler recursion over the atom tree overflows the Ruby thread's
  stack guard otherwise — surfaced as SystemStackError inside
  _register_grammar).
- **Generalized rule boundaries**: rule references serialize as shared
  Named atoms, cyclic through them — the compiler infinite-recursed on
  real grammars until every Named atom / Entity target became a
  subroutine and every reference a call. EXPRESS compiles to 10,195
  instructions.
- **Backtrack budget** (len/64 + 16): measured rates separate grammar
  classes by six orders of magnitude (KV-class 2 backtracks / 47.5 KB;
  EXPRESS ~16/byte). Tripping falls back to the walker for that parse
  and sticks the grammar off (the Ruby VM's sticky-BAIL design).
  Inputs ≥ 8 KiB engage the VM.
- **Diagnostics bridge**: Expected::label() +
  ErrorTracker::expected_labels_at_furthest() feed
  native_failure_message. parse_fresh (expressir's large-file path)
  wired identically via a hash-keyed program cache + sticky set.

Verification: 140-file SRL corpus byte-identical; ruby suite 1224/0.
KV-class large input end-to-end: 47.5 KB in 3 ms. Backtracking-heavy
grammars: walker + one-time registration cost.

## Remaining phases

- **Phase 3 — semantics completion (P1)**: Dynamic/Custom support
  (needs arena-crossing value copies).
- **Phase 4 — VM memoization (P1)**: memoize (position, call-site)
  results in the VM to serve the backtracking-heavy class — removes
  the budget fallback. Then BYTE_DISPATCH from FirstSetAnalysis
  (TODO.max-perf/1 design).

## Status

Phases 1-2 complete (rs#75, rs#76 → 0.6.0/0.6.1); phases 3-4
scheduled.
