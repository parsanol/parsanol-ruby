# WIP: composed PR #22 memo design — 12 spec failures remain

State: PR #22 (pure-Ruby caching/literal-index/safety) squash-merged onto
current main with a composite context.rb:

- main's adaptive activation (probe + backtrack counter) governs when
  memoization engages
- PR's consume_all-scoped keys, prefix-success fallback, and
  cache-unsafety gate (never memoize across dynamic blocks / capture
  writes) gate the active path
- repetition/with_tree_cache keeps main's error paths, PR's
  cache-unsafety replay guard; dynamic callback registration race fixed

Remaining (why this is WIP):
- 12 spec failures at the ruby/native seam: 5 context_specs encode the
  PR's superseded size-threshold design ("immediate caching for unknown
  classes", prefix-success-while-inactive) and need rewriting to the
  composite semantics; the prefix-success boundary specs parse "xy"
  successfully because the run defaulted to the NATIVE engine in the
  test harness — the specs must pin mode: :ruby explicitly
- PR's benchmark suite (benchmark/cache_threshold*) must be run
  main-vs-branch to prove no regression on the adaptive path
- native-parity (tree_parity_83) suite must pass with ruby mode as the
  reference (context changes shift ruby trees is NOT acceptable)
