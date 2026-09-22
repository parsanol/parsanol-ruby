# 8 — Native parity: Rust handles every mode; never fall back to Ruby parsing

Status: COMPLETE — all items shipped through 1.3.26 (see per-item
notes below; cause trees 1.3.23, prefix 1.3.24, reporter 1.3.25,
atom-coverage audit 1.3.26). ITEM 1 DONE (2026-09-16, rs #67 + ruby #44 → 1.3.23).
Remaining: prefix: mode, reporter: feeding, atom-coverage audit (items 2–4).

## Mandate

When the native extension loads and no explicit `mode: :ruby` was given,
Rust must handle ALL modes itself. Ruby parsing is never used as a fallback.

## Implementation plan for item 1 (cause trees) — designed 2026-09-16

The Rust `ParseError` today carries only `Failed { position }`. Parslet-style
cause trees need, per parse attempt that fails:

1. **Failure tracking in `PortableParser`**: a `deepest: Option<(usize /*pos*/,
   Vec<AtomLabel>)>` updated in the `try_atom` failure path. Labels come from
   a new `Atom::label(&self) -> Option<String>` (Str -> the literal, Re -> the
   pattern, Named -> the name, Entity -> rule name) mirroring how the Ruby
   interpreter names expectations. Only track while deeper than the current
   best, so the hot path stays a single compare.
2. **Error payload**: extend `ParseError::Failed` to `Failed { position,
   expected: Vec<String> }` (serde-default so the batch/JSON surfaces stay
   compatible), populate from `deepest` in `parse()`'s failure branch.
3. **FFI contract**: `parse_handle` failure returns `(position, [labels])`
   (Rust builds a small RArray on failure only — the success path stays
   untouched).
4. **Ruby side**: `Parsanol::Native::Parser.parse` builds
   `Parsanol::Cause` from `(position, labels)` — a new
   `Cause.from_native(position, labels, source)` constructor — and raises
   `ParseFailed` directly. Delete the reporter-pass fallback in
   `raise_native_parse_error` (keep the interpreter path only for
   coverage-gap recovery, which success-side stays).
5. **Validation gate**: message-for-message equality with the interpreter's
   two-pass diagnostics across the pubid (7576) + asciichem + molecule
   corpora; failure messages are part of the public contract (pubid wraps
   `#parse_failure_cause`).

Estimate: one focused session. Do NOT land partial — the moment cause
construction diverges, `Cause#ascii_tree` output changes for every user.

## Current fallback sites (parse_native / Native.parse) and what parity needs

1. **Parse failure → Ruby reparse for the cause tree.** The Rust executor
   returns only "Parse failed at position N"; the parslet-compatible
   `ParseFailed` error (deepest-position expected-set cause tree, consumed
   tracking, `#parse_failure_cause` API used by pubid) is built by the Ruby
   interpreter. Parity: port the error-reporter protocol to Rust —
   track the deepest failure (position, expected atom labels) during
   backtracking, return it alongside the failure, and construct the
   `Parsanol::Cause` tree on the Ruby side from that data (no reparse).
   The interpreter's two-pass design (plain attempt + reporter reparse)
   exists because reporting costs allocation; Rust can carry the deepest
   failure state inline at ~zero cost.
2. **`prefix: true`** (partial parse). Native requires full consumption.
   Parity: thread a consume_all flag through `PortableParser::parse` the
   way the Ruby engine does (checked at the root only) — the distributed
   per-branch semantics in Ruby exist for backtracking-into-alternatives;
   replicate at least the root-level check, then the per-branch protocol
   if differentials demand it (see TODO.perf/6 "Next steps" #3).
3. **`reporter:` option** (user-supplied error collector). Same as 1: the
   reporter must be fed from Rust-side failure tracking, via callbacks.
4. **Grammar atoms Rust cannot express.** Dynamic/Cut exist in Rust
   (dynamic callback re-entry, cut terminal). Audit remaining: Capture,
   Infix, Custom, Ignore semantics vs the Ruby atoms; fix or port each.
   Until an atom is proven expressible, `register_grammar` must REJECT the
   grammar up front (fail fast with a clear error) instead of failing at
   parse time and falling back.
5. **Extension missing** (platform gem absent): Ruby fallback is the only
   option — this is the one fallback that stays, and it is explicit
   (environment), not per-parse.

## Non-goals

- `mode: :ruby` remains available as an explicitly requested engine.
- The Ruby bytecode VM stays the fallback engine for no-extension
  environments and as the reference implementation for differentials.
