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
- [x] **SHIPPED (2026-10-24..26, #333/#335 + the audit round)**: the
      lint registry — unpinned-grammar, undocumented-rule,
      capture-without-binding (the binding-coverage lints),
      entry-placement, case-ambiguity (the case-shadow class),
      style-brace-mixing, single-use + dead-rule, core-rule-shadow,
      and `parg lint --suggest-upgrades`. Advisory lints stay out of
      the envelope wire (the advisory split). (ruby#307)

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

- [x] **U1 SHIPPED (2026-10-25, rs#297 tiers + #335's char columns)**:
      codepoint-exact `.`/negated classes; byte offsets stay the wire.
- [x] **U2 SHIPPED (2026-10-25, the unicode fold rounds)**: `%i` =
      Unicode simple case folding, one table everywhere
      (unicode_fold/unicode_hard corpus fixtures byte-identical).
- [x] **U3 SHIPPED (2026-10-25, #334 + the tables)**: category tables
      with compile-time misspelling rejection; the corpus replays
      byte-identically. Remaining (owner-gated): the table-version
      wire clause.

### T5 — tooling

- [x] **SHIPPED (2026-10-24, #318 merged)**: ABNF importer hardening —
      the RFC corpus (5234/3339/3986/8259 + edge matrix) with
      acceptance pins riding each import; five importer fixes
      (continuation lines, the %i token, the 0<prose> idiom, =/ dedupe,
      nullable-last reorder with fixpoint nullability).
- [x] **SHIPPED (2026-10-24, #328)**: ABNF corpus tails — RFC 5322
      address, RFC 9110 field lines, JOSE compact; two importer fixes
      the pins forced (RFC 5234 quoted strings carry no escape
      mechanism; emit_string's String-replacement gsub silently
      dropped backslash escaping).ruby#305 closed.
- [x] **SHIPPED (2026-10-24, #320)**: ANTLR importer scoped v1 —
      parser/lexer rules, char sets → %x alternations, the ~[set]
      idiom, EOF dropped, everything out of scope rejected with
      position and guidance; corpus replayed through acceptance pins.
- [x] **SHIPPED (2026-10-24, #317 merged)**: `parg diff` — grammar
      semver classification (major/minor/patch), --json/--suggest-bump/
      --check LEVEL.
- [x] **SHIPPED (2026-10-24..26, #331 + ruby#346)**: Bindings v2 —
      compile-time path validation (fails the build naming the
      segment), the binding-coverage lints, and shape-derived typed
      emission in three languages (`parg schema --ts/--ruby/--rust`)
      whose generated models materialize the bound output; the
      cross-engine bound-output differential is the corpus itself.
      (ruby#308)
- [x] **SHIPPED (2026-10-25..26, rs#316/#318/#319/#321/#324)**: PARG
      frontend in Rust — byte-parity with the Ruby compiler (39 atom
      streams, 37 envelopes, 47 order_warnings, 47/47 flavor sources),
      trivia injection, leftrec tiers, imports, the lint port, and the
      wasm `compileSource` (the browser compiles live; site#37's
      author tab). (rs#298, site#19)

- [x] **SHIPPED (2026-10-26, ruby#344 + ruby#345)**: constrained
      decoding, first-class — `parg export --target xgrammar` (with
      the constructs that have no equivalent rejected naming them),
      the acceptance differential through the REAL XGrammar runtime
      (60/71 identical; every mismatch = the measured
      CFG-vs-ordered-choice class), and the resync partial-mask
      story: the recovery export mode lowers declared resync patterns
      as escape alternatives at the spine, gated by the seeded
      differential against the engines' own recovery path.

## The completion map (the full graph; nodes, dependencies, gates)

Node = work; "after" = dependencies; Gate = Definition of Done. No node
is done until its gate is green and merged.

**A — correctness debt (first; everything is judged by these)**
- **A1** rs#305 registered-program consume-all — **RESOLVED
  (2026-10-24, closed)**: the acceptance was a stale pre-#300 local
  bundle; current code's VM-short-to-walker gate rejects on every tier.
  Gate met: `vm_path_spec` green on a freshly compiled 0.18.21+ ext;
  the acceptance map folds to three tiers (full / partial /
  full-by-contract).
- **A2** CI cache-version bump (rake.yml) + parity-failure field diff —
  **DONE**: `cache-version: v1` pins the ext cache (no stale-ext
  runs); the parity gates print got/want diffs on drift.
- **A3** selfhost + pubid-grammar refresh (braces + core rules in the
  language grammar) — **DONE (2026-10-24, pubid-grammar#58 +
  #329)**: PgMeta carries a bw-threaded brace-form expression tier,
  brace_rule written in the brace form it recognizes, artifact rebake
  on 1.3.108 (RUBY_REF bumped to a brace-capable compiler);
  SelfHost.valid? accepts brace-form sources (spec #329).

**B — language wholeness**
- **B1** modern capture impl (ruby#304) — after: owner picks the mode
  name. Gate: dual-mode corpus byte-identical across engines;
  `parg lint --captures` matches the rewrite corpus-wide.
- **B2** bindings v2 (ruby#308) — after: none (spec #319 merged; lints
- **B2** bindings v2 (ruby#308) — **DONE (2026-10-24)**: compile-time
  path resolution fails the build naming the segment (#331 — capture
  in its rule's subtree; `[]` needs the capture under a repetition,
  its own body's repetition counting; malformed shapes rejected; the
  orphan coverage warning subsumed), and ruby/ts/rs bound trees agree
  on the parity grammars — enforced, not stated: ruby↔rs via the
  parg_bindings job, ruby↔ts via pubid-ts#141's bound replay in the
  cross-engine gate (first run 260 tree + 7 bound cases, zero
  drift).
- **B3** ABNF corpus tail (5322/9110/JOSE) — **DONE (2026-10-24,
  #328)**: each imports, compiles, replays; 14 corpus examples.
- **B4** ANTLR corpus growth (SQL/JSON/config + rejection matrix) —
  **DONE (2026-10-24, feat/antlr-corpus-growth)**: JSON / SELECT /
  properties grammars replayed through acceptance pins; the corpus
  forced two importer fixes (multi-line block comments never lexed;
  plain charset chars ran through the escape table, so [Tt] meant
  TAB) and the contract now enforced (non-greedy quantifiers
  rejected, not read as greedy+optional).
- **B5** lint completion (entry-placement, case-ambiguity, single-use,
  `--suggest-upgrades`) — PARTIAL (2026-10-24, this branch): single-use
  + dead-rule lint shipped (advisory; entry roots, injected core rules,
  and resync-tier rules exempt); case-ambiguity shipped (a
  case-insensitive earlier literal shadows a case-equal later literal
  — build failure, the prefix-shadow class); --suggest-upgrades
  shipped (`parg lint` command: errors exit 1, all warnings printed;
  the flag adds CoreRuleDuplicates suggestions — bare-class rules
  duplicating a core rule, and the hand-rolled CRLF sequence —
  unregistered, suggestion surface only); entry-placement shipped
  (declaration-order trace in the parser; canonical placement = the
  foot of the grammar block, the corpus-wide precedent; advisory).
  Gate: each fires on a fixture, silent on the corpus.

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
- **E1** rs#298 PARG frontend in Rust — **DONE (2026-10-26, closed)**:
  the parity corpus IS the gate and it is green on every axis (39 atom
  streams, 37 envelopes, 47 order_warnings, 47/47 flavor sources).
- **E2** wasm live compilation (site#19) — **DONE (2026-10-26,
  closed)**: `compileSource` + the playground Author tab (site#37).
- **E3** site#23 tour mirror — site#23 merged; the tour page mirrors
  the guide's canonical forms. Any future guide section rides the
  same mirror rhythm.
- **E4** python packaging — after: owner picks name/floor +
  trusted-publisher. Gate: wheels on PyPI, CI smoke green. (OPEN,
  owner-gated.)

**F — frontiers (beyond-SOTA proper)**
- **F1** #321 constrained decoding — **DONE (2026-10-26, closed)**:
  the acceptance differential runs through the real XGrammar runtime,
  and the resync-driven escape grammars (ruby#345) are the
  partial-mask story, gated by the seeded differential.
- **F2** rs#304 recovery metrics — **DONE (2026-10-26, closed)**: the
  seeded harness is engine-identical (the convergence train), the
  table is published with the comparative columns measured
  (tree-sitter 62/64 at 0.66 precision; parslet/pest 0/64 by
  construction), and the twin-harness pins are the no-regression
  gate. (rs#323 + rs#326.)
- **F3** verified core (Task 8B) — Track A done; B1 shipped; B2 run
  once and archived; B3 deferred with re-trigger conditions (the
  owner's 2026-10-22 decision). Per the scoping doc: CLOSED as
  scoped.

**Critical path**: A → (B ∥ C ∥ E1) → E2/D1/D2 → F. F1/F2 start
anytime. **State (2026-10-26): every node is DONE, CLOSED, or
owner-gated.** Owner unblocks outstanding: the mode name (B1/T3), the
U3 table-version wire clause, python identity (E4), the quiet host
(D1 — until then the performance absolutes stay unpublished and the
recovery table stands alone), and codegen's in-process bench (D2).

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
