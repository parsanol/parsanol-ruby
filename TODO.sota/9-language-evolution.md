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
