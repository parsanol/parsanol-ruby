# 11. Large-input memoization (parsanol-ruby#52)

## Symptom

Giant EXPRESS schemas (380–622 KB) parsed at up to ~30x the per-KB CPU
cost of normal schemas (e.g. `aic_machining_feature.exp`: 605 KB,
60.4 s CPU, 99.8 ms/KB vs 4 ms/KB for small schemas). A `sample(1)`
profile showed ~99% of 63k frames in `PortableParser::try_atom` /
`parse_atom_uncached` mutual recursion with `DenseCache::insert` in
only 2 frames — memoization contributed nothing.

## Root causes (both in parsanol-rs portable parser)

1. `compute_no_cache` marked ~90% of atom kinds as no-cache
   (Str, Re, Sequence, Named, Entity, Lookahead, Cut, Ignore,
   Capture, Scope). Only Alternative/Repetition/Dynamic/Custom were
   memoized, so every non-terminal subtree was re-executed from each
   structural path that reached it. Note the JSON registration path
   (used by the Ruby FFI) was the only path where this policy was
   computed; grammars built with the Rust DSL were already fully
   memoized.
2. `DenseCache::insert` silently dropped entries once `max_entries`
   (clamped to 2M by `DenseCache::for_input`) was reached — the cache
   filled within the first fraction of a large file and memoization
   was then permanently off for the rest of the parse.

## Fix (parsanol-rs PR #71)

- Memoize every atom kind: all atoms are pure functions of
  (input, position), successes and failures alike.
- On reaching `max_entries`, recycle the cache and keep inserting:
  memory stays bounded, and the recently-inserted window that
  backtracking re-visits stays warm.
- `benches/large-input.rs` pins the regression through
  `Grammar::from_json` (the FFI registration path).

## Results (Expressir native tier, ISO 10303 SRL corpus, arm64-darwin,
parse+build CPU)

| file | size | before | after | speedup |
|---|---:|---:|---:|---:|
| aic_machining_feature.exp | 605 KB | 99.8 ms/KB (60.4 s) | 12.0 ms/KB (7.3 s) | 8.3x |
| geometry_schema.exp | 385 KB | 63.6 ms/KB (24.5 s) | 29.1 ms/KB (11.2 s) | 2.2x |
| action_schema.exp | 46 KB | 15.7 ms/KB (0.73 s) | 7.3 ms/KB (0.34 s) | 2.2x |

Per-KB cost is flat instead of climbing ~6x with size; small and
mid-size schemas are neutral-to-faster. Corpus pass/fail set is
identical (135/140 ok; the 5 failures pre-date the fix). Spec suite
1220 examples, 0 failures.

Known trade-off: on a zero-backtracking micro-grammar full
memoization costs +11–27% (pure overhead, no reuse) — every real
corpus measured improved.

## Verification rig

- Corpus: `~/src/mn/iso-10303/schemas/resources` (140 files), driven
  through `Expressir::Express::Parser.from_file` with
  `-I ~/src/parsanol/parsanol-ruby/lib -I ~/src/lutaml/expressir/lib`.
- A/B by swapping `lib/parsanol/parsanol_native.bundle` (ext built
  from rs main vs rs fix branch via a temporary workspace-root
  `[patch."https://github.com/parsanol/parsanol-rs"]` path override
  in parsanol-ruby — do not commit that override).
