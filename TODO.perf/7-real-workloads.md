# 7 — Real-workload correctness and performance (asciichem, pubid)

Status: FIXED + measured (2026-09-15)

## Method

Mirror each consumer's grammar onto the Parsanol parslet-compat shim with
zero code changes (subclass swap), then diff full parse trees against real
parslet on the consumer's own fixture corpus, plus wall-clock benchmarks.
Harnesses: `/tmp/real_asciichem.rb`, `/tmp/real_pubid.rb` (recreatable from
this file's description; canonical versions should land in `benchmark/`).

## Results after fixes

- asciichem: 18/18 real inputs identical (parslet == ruby == native)
- pubid ISO: 7572/7573 fixtures identical (the 1 is a fixture artifact
  where the extracted string fails in both parslet and parsanol)
- pubid ISO perf: parslet 0.25s, parsanol ruby 0.42s (0.6x),
  native 0.11s (2.3x)

## Bugs found (all fixed 2026-09-15)

1. **Rust `Grammar#optimize` mutated shared atoms** (parsanol-rs
   `portable/grammar.rs`): merging an adjacent Str/Re run in one sequence
   OVERWROTE the first atom's pattern in place; every other sequence
   referencing that atom silently matched the merged pattern. This alone
   made the entire pubid ISO root grammar fail natively (a shared
   `str(" ")` merged into `str("  ")` broke every other `space` use).
   Fix: merged runs are appended as NEW atoms; originals are never
   mutated; compaction removes them when unreferenced.
   Minimal repro: `s = str("ab"); (s >> str("c")) | (s >> str("d"))` —
   "abc" and "abd" must both parse.
2. **Ruby fallback double-transform** (`native.rb`): when the native parse
   failed and the pure-Ruby fallback succeeded, `Native.parse` ran
   `BatchDecoder.decode_and_flatten` on the fallback's already-final tree;
   the AstTransformer heuristics then collapsed `{k: [{j: v}]}` to
   `{k: {j: v}}` (823 pubid fixtures). Fix: decode inside the native
   success paths only; return fallback results directly.
3. **`:mode` ignored in options hash** (`parser.rb`): `parse(input,
   {mode: :ruby})` — exactly the call shape a `Parslet::Parser` subclass
   produces when forwarding options via `super` — fell into the legacy
   branch and silently used native. Fix: `:mode` is honored wherever it
   appears (hash, kwarg, or positional symbol).
4. **AstTransformer tag/symbol + double-wrap** (`native/transformer.rb`):
   the Rust handle path tags arrays with Symbols (`:repetition`) but
   `transform_single_key_hash` only matched the String form; empty
   repetitions decoded to `""@0` instead of `[]`, and once tagged
   correctly, named children were re-wrapped with the parent key
   (`{copublishers: [{copublishers: ...}]}`). Fix: accept both tag forms;
   hash items keep their own names.

## Standing items

- Root-level incomplete-consumption divergence in native (see
  TODO.perf/6-ruby-vm.md "Next steps" #3): correct via fallback, but costs
  a failed native attempt + full Ruby reparse on such inputs.
- The pubid differential harness should be checked in under `benchmark/`
  with a vendored fixture subset (upstream fixture corpus is large).
