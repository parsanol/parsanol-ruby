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

- [ ] Tour/guide: example-pin syntax (`accept`/`reject`/`capture`/
      `shape`/`example`), style guide section, `#` vs `##` documented.
      (ruby#310, site#23)
- [ ] Lint suite: `unpinned-grammar`, `undocumented-rule`,
      `capture-without-binding`, `entry-placement`, `case-ambiguity`,
      `style-brace-mixing`, `single-use-rule`; `--suggest-upgrades`.
      (ruby#307)

### T1 — core rules (ruby#303)

- [ ] RFC 5234 prelude (16 rules), shadowable; `core-rule-shadow` lint;
      ABNF importer stops emitting them. Spec: guide "Core rules".

### T2 — self-delimiting rules (ruby#302)

- [ ] `name = { ... }`: newlines whitespace inside, extent = matching
      `}`, doc-comment attachment structural. Spec: guide "Rule
      bodies: the brace form" (PR #301). Selfhost + pubid-grammar
      `parg.json` update; whole-corpus recompile diff = empty.

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
