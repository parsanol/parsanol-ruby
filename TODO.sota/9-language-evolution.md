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

- [x] **SHIPPED (2026-10-24, #310-in-flight)**: guide — pin syntax was
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

- [ ] `mode "modern"`: compile-time `Named(rule_name)` wrap — engines
      unchanged; envelope records the mode; `parg lint --captures`
      reports legacy-grammar shape deltas.

### T4 — Unicode native (rs#297)

- [ ] U1 correctness floor (codepoint-exact `.`/negated classes, char
      columns; byte offsets stay the wire).
- [ ] U2 `%i` = Unicode simple case folding, one table everywhere.
- [ ] U3 category tables (wasm feature-gated). Unicode corpus replayed
      byte-identically across all engines per tier.

### T5 — tooling

- [ ] ABNF importer hardening: RFC corpus (5234/3339/3986/5322/8259/
      9110/JOSE), reviewable order-dependence reports. (ruby#305)
- [ ] ANTLR importer, scoped subset. (ruby#309)
- [ ] `parg diff` grammar semver. (ruby#306)
- [ ] Bindings v2: typed trees, compile-time path validation, per-
      language emission parity. (ruby#308)
- [ ] PARG frontend in Rust: byte-parity with the Ruby compiler on a
      source corpus → wasm compiler (browser compiles live), Ruby-free
      native compilation for C/C++/Python/CLI. (rs#298, site#19)

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
