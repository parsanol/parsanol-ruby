# 9 — Language evolution: beyond parslet, beyond SOTA

**Mission (owner directive, 2026-10-24):** PARG replaces ABNF as the
grammar language of record and ANTLR as the parser-generation workhorse.
The parslet wire shape is a *migration contract* (corpus-pinned so all
engines stay byte-identical) — not the ceiling. Unicode-native is a
requirement, not a roadmap item; ASCII bytes remain the wire contract.

The structural asset the whole program rides on: **artifacts are the
wire**. Language changes are compiler-only unless semantics change; the
five runtimes keep working untouched.

## Owner decisions taken

- Brace-delimited rule bodies land in 1.x (additive — verified: no
  rule body in any of the 67 ecosystem sources contains `{`).
- Core rules are shadowable, never reserved (zero breakage; lint
  carries the migration).
- Unicode-native is scheduled work (tiered), not a documented ceiling.

## Tiers

### T0 — docs + lints (no semantics)

- [x] **SHIPPED (2026-10-24, #312 merged)**: guide — pin syntax was
      already complete (all five forms); added the style guide, the
      `#` vs `##` distinction, the `%i` raw-capture fact, and the
      canonical brace-form quick start with tests + bindings. Site
      tour mirror remains: site#23.
- [ ] Lint suite: `unpinned-grammar`, `undocumented-rule`,
      `capture-without-binding`, `entry-placement`, `case-ambiguity`,
      `style-brace-mixing`, `single-use-rule`; `--suggest-upgrades`.
      (ruby#307)
- [ ] Lint suite: `unpinned-grammar`, `undocumented-rule`,
      `capture-without-binding`, `entry-placement`, `case-ambiguity`,
      `style-brace-mixing`, `single-use-rule`; `--suggest-upgrades`.
      (ruby#307)

### T1 — core rules (ruby#303)

- [x] **SHIPPED (2026-10-24, #311 merged)**: RFC 5234 prelude,
      shadowable — class members via BUILTIN_CLASSES (+11), CRLF/LWSP
      injected transitively in atom_for. Whole-corpus gate byte-stable.
      `core-rule-shadow` lint remains (ruby#307); ABNF importer
      emission update rides ruby#305.

### T2 — self-delimiting rules (ruby#302)

- [x] **SHIPPED (2026-10-24, #311 merged)**: brace bodies — newlines
      whitespace inside, extent = matching `}`, doc attachment
      structural, `{` may sit on the line after `=`. Whole-corpus
      recompile diff empty (67/67). Remaining: selfhost + pubid-grammar
      `parg.json` refresh, the `style-brace-mixing` lint (ruby#307).

### T3 — implicit capture, opt-in dialect (ruby#304)

- [x] **SPEC SHIPPED (2026-10-24, #315 merged)**: the wrap table,
      compile-time lowering tower, the envelope `mode` field, and
      major-versioning for shape changes. Implementation awaits ONE
      owner decision: the mode's spelling. `parg lint --captures` and
      the modern-mode corpus ride the implementation.

### T4 — Unicode native (rs#297)

- [ ] U1 correctness floor (codepoint-exact `.`/negated classes, char
      columns; byte offsets stay the wire).
- [ ] U2 `%i` = Unicode simple case folding, one table everywhere.
- [ ] U3 category tables (wasm feature-gated). Unicode corpus replayed
      byte-identically across all engines per tier.

### T5 — tooling

- [x] **SHIPPED (2026-10-24, #318 merged)**: ABNF importer hardening —
      the RFC corpus (5234/3339/3986/8259 + edge matrix) with
      acceptance pins riding each import; five importer fixes
      (continuation lines, the %i token, the 0<prose> idiom, =/ dedupe,
      nullable-last reorder with fixpoint nullability). Remaining:
      RFC 5322/9110/JOSE fixtures (ruby#305 stays open for them).
- [x] **SHIPPED (2026-10-24, #320)**: ANTLR importer scoped v1 —
      parser/lexer rules, char sets → %x alternations, the ~[set]
      idiom, EOF dropped, everything out of scope rejected with
      position and guidance; corpus replayed through acceptance pins.
- [x] **SHIPPED (2026-10-24, #317 merged)**: `parg diff` — grammar
      semver classification (major/minor/patch), --json/--suggest-bump/
      --check LEVEL.
- [ ] Bindings v2: typed trees, compile-time path validation, per-
      language emission parity. Spec shipped (#319); first slice = the
      two binding lints. (ruby#308)
- [ ] PARG frontend in Rust: byte-parity with the Ruby compiler on a
      source corpus → wasm compiler (browser compiles live), Ruby-free
      native compilation for C/C++/Python/CLI. (rs#298, site#19)

## The completion map (the full graph; nodes, dependencies, gates)

Node = work; "after" = dependencies; Gate = Definition of Done. No node
is done until its gate is green and merged.

**A — correctness debt (first; everything is judged by these)**
- **A1** rs#305 registered-program consume-all — gate: `vm_path_spec`
  green on a freshly compiled 0.18.21+ ext; the acceptance map folds to
  three tiers (full / partial / full-by-contract).
- **A2** CI cache-version bump (rake.yml) + parity-failure field diff —
  gate: no stale-ext runs; a forced drift prints its diff in CI.
- **A3** selfhost + pubid-grammar refresh (braces + core rules in the
  language grammar) — gate: self-host validates brace-form sources.

**B — language wholeness**
- **B1** modern capture impl (ruby#304) — after: owner picks the mode
  name. Gate: dual-mode corpus byte-identical across engines;
  `parg lint --captures` matches the rewrite corpus-wide.
- **B2** bindings v2 (ruby#308) — after: none (spec #319 merged; lints
  shipped). Gate: path resolution fails the build naming the segment;
  ruby/ts/rs bound trees agree on the parity grammar.
- **B3** ABNF corpus tail (5322/9110/JOSE) — gate: each imports,
  compiles, replays.
- **B4** ANTLR corpus growth (SQL/JSON/config + rejection matrix) —
  gate: same harness, green.
- **B5** lint completion (entry-placement, case-ambiguity, single-use,
  `--suggest-upgrades`) — gate: each fires on a fixture, silent on the
  corpus.

**C — unicode native**
- **C1** U1 char-based columns — after: OWNER GO (wire-coordinated
  corpus re-bake). Gate: all engines byte-identical on the re-bake.
- **C2** U2 simple case folding — gate: fold-equivalent fixtures
  identical everywhere.
- **C3** U3 category tables — gate: same; wasm payload within budget.

**D — fast, published**
- **D1** quiet-host benchmark publication — after: a quiet host.
  Gate: honest table + closing-gap numbers published.
- **D2** codegen in-process bench — gate: generated numbers without
  pipe overhead.
- **D3** incremental at tree-sitter grade (Task 7) — the research pole.
  Gate: ≥4/5 edits spliced at 25 KB+; sub-ms keystrokes; == full-reparse
  acceptance.

**E — distribution (the keystone path)**
- **E1** rs#298 PARG frontend in Rust — THE longest pole; start parallel
  with B. Tiers: lexer → parser → compiler. Gate: source-corpus parity
  (ruby-compiled == rust-compiled, byte-for-byte) green for N
  consecutive releases.
- **E2** wasm live compilation (site#19) — after: E1. Gate: the browser
  compiles a typed grammar live.
- **E3** site#23 tour mirror — after: owner merges site PR #20.
- **E4** python packaging — after: owner picks name/floor +
  trusted-publisher. Gate: wheels on PyPI, CI smoke green.

**F — frontiers (beyond-SOTA proper)**
- **F1** #321 constrained decoding — after: none. Gate:
  acceptance-equivalence corpus; resync-driven partial-mask demo.
- **F2** rs#304 recovery metrics — after: none. Gate: seeded harness,
  engine-identical, published table, no-regression gate.
- **F3** verified core (Task 8B) — after: A. Gate: per the scoping doc.

**Critical path**: A → (B ∥ C ∥ E1) → E2/D1/D2 → F. F1/F2 start anytime.
Owner unblocks: mode name (B1), U1-columns go (C1), python identity
(E4), site PR #20 (E3), quiet host (D1).

## The beyond-SOTA frontier (owner directive 2026-10-24: "PARG must be
## beyond SOTA fully")

Beyond replacing ABNF and ANTLR, two frontiers are uncharted — no
grammar toolkit occupies them:

- **Constrained generation, first-class** (ruby#321): one artifact
  feeds human tooling AND the decoder — `parg export` lowers to
  XGrammar/llguidance token masks, with the property that target-engine
  acceptance ≡ parsanol acceptance, pinned by the differential corpus.
  Resync-enabled artifacts drive partial-mask semantics after a
  violation — no grammar format has recovery-aware constrained
  decoding.
- **Recovery quality as a published metric** (rs#304): seeded
  corruption models, a recoverable-fraction/precision/bytes-to-recovery
  harness, engine-identical by the differential gate, published beside
  the honest performance table, and a no-regression release gate.
  Recovery today is folklore everywhere else; this makes parsanol's the
  only measured one.

Plus the existing differentiators to protect: PEG predictability by
construction, compile-time left-recursion rewriting through the
unchanged artifact format, checksummed provenance with embedded tests
replayed differentially across five engines, declarative resync
recovery, compile-time-validated typed bindings, and grammar semver
tooling (`parg diff` — shipped).

## Replacement thesis (how this wins)

- **ABNF**: importability + strict superset. An RFC grammar becomes a
  checksummed artifact with embedded tests, typed bindings, and a
  five-engine runtime — strictly more than the ABNF it came from.
- **ANTLR**: PEG predictability by construction + compile-time
  left-recursion rewriting + typed bindings (compile-time-checked, vs
  listeners/visitors) + one artifact across five runtimes via the C
  ABI — stated honestly against ALL(*)'s ambiguity tolerance.
- **Performance**: the closing-gap bench (parsanol-codegen) publishes
  the generated backend beside the interpreted paths; incremental
  stays Tier 7.
