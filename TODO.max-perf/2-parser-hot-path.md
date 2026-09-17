# 2. Parser hot-path streamlining (P0)

## Why

`try_atom` executes on every atom attempt (~2M+ per giant schema).
Two per-call costs are now pure overhead:

1. `check_resources()` runs a multi-branch resource check per call.
   It must collapse to a single counter compare on the hot path, with
   the expensive branches taken only when the budget actually trips.
2. The `is_no_cache` gate is definitionally dead since full
   memoization (TODO.perf/11) — the bitset is kept for semver
   stability, but the hot path should not pay a bounds-checked Vec
   index per atom attempt.

## Design

- Budget check: decrement-then-test one `steps_remaining` counter;
   recursion-depth guard likewise. No allocation, no method call that
   the compiler cannot fully inline.
- Hot path reads the no-cache policy from a cached bool/empty-check
   decided once per parser construction, not per atom.
- Measure with `benches/large-input.rs` (criterion) and the expressir
  giant-schemas bench; no win ships without a measured delta.

## Acceptance gates

- Same as TODO.max-perf/1 (suite, clippy, differentials, corpus).

## Status

**DONE.** The governor was already interval-gated (timeout off by
default, memory checked every 1000 ops) — the real waste was
`PortableParser::check_resources` computing `arena.memory_usage() +
cache.memory_usage()` on EVERY atom attempt even with no limit set.
`ResourceGovernor::check_resources_lazy` now measures memory only when
a limit is set AND the interval is reached (OCP: `check_resources`
keeps its contract; the lazy variant is additive).

`benches/large-input.rs` (criterion, p = 0.00): 2 KB -29%, 64 KB
-18.5%, 64 KB fail-at-end -29%. Suite + clippy green.

The dead `is_no_cache` Vec index was audited and left in place: it is
a single bounds-checked load, and removing the hot-path call would
diverge from the (semver-frozen) public `is_no_cache` API for no
measurable gain.
