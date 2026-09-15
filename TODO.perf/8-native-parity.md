# 8 — Native parity: Rust handles every mode; never fall back to Ruby parsing

Status: MANDATED (2026-09-15); not yet implemented

## Mandate

When the native extension loads and no explicit `mode: :ruby` was given,
Rust must handle ALL modes itself. Ruby parsing is never used as a fallback.

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
