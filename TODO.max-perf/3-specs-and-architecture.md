# 3. Specs and architecture quality (P1)

## Why

The last two perf rounds (parsanol-ruby#52 fix, expressir#348) were
verified by corpus byte-equality — the strongest possible gate — but
shipped no focused regression SPECS for the new invariants. Quality
rules for this codebase (OCP, MECE, model-driven) require the
invariants to be pinned so future refactors cannot silently undo them.

## Design

### parsanol-rs specs

- `Grammar::from_json` (the FFI registration path) memoizes every
  atom kind: `no_cache` is empty / all-false for any grammar.
- `DenseCache::insert` recycles at `max_entries` instead of freezing:
  after the cap is reached, previously-missing keys still hit (len
  bounded, drops counted), and stale entries from before a recycle do
  not resurrect.
- First-byte analysis (TODO.max-perf/1): disjoint alternatives get a
  table; nullable/UNKNOWN branches do not; cycles terminate as
  UNKNOWN.

### expressir specs

- `RemarkAttacher`: the WHERE-clause index maps `WHERE <id>:` labels
  to line numbers case-insensitively, keeps multiple same-id
  occurrences ordered, and per-remark targeting matches the
  sequential semantics it replaced.
- `ScopeResolver#find_by_position`: identical results to the linear
  scan for remark lines on and across 1024-line bucket boundaries,
  including span-huge nodes (schema spans everything) and the
  Repository/Cache exclusions.
- `ModelElement#source`: memoized (same object returned), and the
  lutaml-model `source=` setter does not leak into the formatted
  reader (include_source parity — the exact regression that the
  corpus gate caught during expressir#348).

### Architecture review (MECE/OCP)

- Line-indexing concern lives in exactly one place per class that
  needs it; ScopeResolver owns line→scope resolution, RemarkAttacher
  owns WHERE-clause membership (documented in-code as intentional).
- No new public API on `Grammar`/`PortableParser` for analysis state
  (semver contract; out-of-band storage instead).

## Status

**DONE.**

- parsanol-rs: `test_from_json_memoizes_every_atom_kind` (registration
  path leaves no atom uncached) and `test_recycles_at_cap_instead_of_
  freezing` (DenseCache recycles, stays bounded, recent inserts hit) —
  shipped in parsanol-rs#73. First-byte-analysis specs are deferred to
  the VM work (TODO.max-perf/1 superseded its standalone form).
- expressir: regression specs for find_by_position bucketing (crossing
  the 1024-line boundary, last-container order, Repository exclusion,
  nil outside spans), the WHERE-clause index (case-insensitivity,
  repeated labels, non-WHERE lines), and ModelElement#source
  (memoization + setter independence) — lutaml/expressir#350.
- Architecture review: analysis state stays off the semver-frozen
  Grammar surface (out-of-band precedent); engine selection remains a
  registration-time concern (OCP); no new doubles anywhere.
