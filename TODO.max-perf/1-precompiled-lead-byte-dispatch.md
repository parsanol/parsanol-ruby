# 1. Precompiled lead-byte dispatch (P0)

## Why

After full memoization (TODO.perf/11), the native parse runs at
2.5–6 ms/KB with ~99% of samples inside `try_atom`/`parse_atom_uncached`
recursion. The remaining cost is per-atom interpretation: enum-match
dispatch and sequential ordered-choice probing. The 2022–2026 state of
the art (XGrammar-2's TagDispatch, Pest's automata, our own Ruby VM's
BYTE_DISPATCH — TODO.perf/6) all precompute grammar structure at
registration and discriminate alternatives on the lead byte instead
of probing branches one by one.

## Design

- **Registration-time analysis** walks the atom graph once and
  computes, for every atom, a conservative first-byte superset:
  - `Str` → its first byte.
  - `Re` → first byte of the regex's required literal prefix
    (regex-syntax `Hir` properties); a non-empty literal prefix
    implies non-nullable. No prefix (nullable-or-unprovable) →
    UNKNOWN = "can start with anything".
  - `Sequence` → first set of the leading element while provably
    non-nullable; otherwise UNKNOWN.
  - `Alternative` → union over branches.
  - `Repetition` min ≥ 1 → inner first set; min = 0 → nullable.
  - `Named`/`Entity`/`Ignore`/`Capture`/`Scope` → propagate child
    (cycle-guarded; cycles → UNKNOWN).
  - `Lookahead`/`Cut`/`Dynamic`/`Custom`/`Any` → UNKNOWN.
- **Dispatch table**: for each `Alternative`, a 256-entry
  `byte → first branch index whose superset contains the byte`.
  Stored next to the per-parse mutable state (NOT on `Grammar` —
  adding fields to the pub struct breaks semver; see TODO.perf/11
  out-of-band precedent), computed once per grammar and reused
  across parses.
- **Semantics**: the table only ever SKIPS branches that provably
  fail at their first terminal. When the chosen branch fails, the
  full sequential ordered-choice path runs — so failure positions,
  expected-label accumulation, and deepest-failure diagnostics stay
  byte-identical. Nullable/UNKNOWN branches never discriminate; they
  fall back to sequential probing.

## Acceptance gates

- parsanol-rs test suite + clippy green.
- parsanol-ruby full spec suite (parslet/native differential) green.
- ISO 10303 SRL corpus (140 files) via expressir: identical output,
  no per-KB regression; giants improve.
- `benches/large-input.rs` before/after.

## Status

**Superseded by TODO.max-perf/4 findings.** Investigation revealed the
parsanol-rs tree already contains a full bytecode VM (LPeg-style stack
machine, ~6,300 lines: compiler/vm/optimizer/pattern-analysis) that was
never wired into any production path — and, as the new differential
harness exposed, never worked for reference-based grammars at all (see
TODO.max-perf/4's defect inventory). Hand-rolling a separate lead-byte
table inside the tree-walker would duplicate the VM's existing
FirstSetAnalysis machinery; the correct move is to complete the VM and
bake dispatch into its Choice compilation (FirstSetAnalysis already
computes charsets + nullability). This item's design is now IMPLEMENTED in the VM's compiler
(BYTE_DISPATCH, rs#78 → 0.7.0) — see TODO.max-perf/4.
