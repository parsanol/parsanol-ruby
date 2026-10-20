# 6 — Compact packrat memory discipline

Status: done with a documented deviation — Tier 2. Bound formalized
and pinned (parsanol-rs#256): cache ≤ ~62 MiB per parser (24 B ×
clamp(input×atoms, 4096, 2M) plus the slot table); `cache_memory_usage`
exposed; an all-snapshot slot-table doubling bug fixed; 600 KB
regression test added.

The spill tier is **not shipped**: giant measurements (633 KB JSON)
showed 203 MB peak RSS (Rust), 300 MB (Ruby native), 297 MB (Ruby VM),
of which the cache is only ~62 MB — the arena and output conversion
dominate. Spilling cache entries therefore cannot deliver the win the
item targets; the measured negative and the arena/output lever are
recorded in the PR. Revisit spill only if a future bound makes the
cache the dominant tier.

## SOTA reference point

**Ford's compact packrat**: never DROP a parse result — spill to
secondary storage instead, keeping O(n) time with bounded memory. The
academic bound the practical work here has approximated.

## Current state (do not rebuild)

- All atoms memoized (rs#71); cache caps + recycle-at-cap (rs#120-era);
  snapshot tier for incremental sessions (32 MiB budget guard);
  DenseCache experiments with measured negatives on record (dense
  preallocation 1.8x regression — TODO.perf/7).

## Task

1. Formalize the current policy's memory bound (what IS the worst case
   today?) and document it next to the code.
2. Spill tier for giant inputs: cache entries beyond the cap go to a
   compact serialized form (the program-artifact cache already has a
   versioned format to reuse) instead of being recycled; measure
   expressir-giant inputs (600 KB+) end-to-end.
3. Benchmark memory-vs-time against the recycle policy; ship only on a
   measured win (the dense-memo negative result is the precedent —
   honest negatives stay documented).

## Acceptance

Documented bound; spill tier behind a flag until it proves itself;
regression pins for the giants; no regression on the
zero-backtracking micro-grammar class (+11-27% memoization overhead
known trade-off unchanged or better).
