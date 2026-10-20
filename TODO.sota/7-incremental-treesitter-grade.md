# 7 — Incremental parsing to tree-sitter grade

Status: in progress — Tier 2. The retained session keeps whole
containers and splices repetition-spine documents. Added: a 500-edit,
multi-region differential gate (retained result == full reparse after
every edit) and `parsanol/examples/keystroke.rs`, a release-mode probe
(parsanol-rs#257).

Measured gap (contended host; latencies indicative, engagement counts
exact): 5.8 KB document 0.034 ms/edit with 4/5 edits spliced; 11.8 KB
9.3 ms with 1/5; 25.8 KB 97.5 ms with 0/5; a 600 KB document did not
complete 20 tail edits in ten minutes (probe stopped). Reuse plateaus
at ~3k entries while the eligible prefix grows linearly. **The
sub-millisecond-on-giants target is not met.** The engagement collapse
is filed as parsanol-rs#258 with reproduction and hypotheses; closing
requires engagement to scale and <5 ms on 600 KB. Error-tolerant
incremental parses also remain (recovery composed with the session).

The engine work lives in parsanol-rs; the session API is shared with
Ruby.

## Where we are

IncrementalParser with snapshot-tier retention: ~1.5-1.7x per
keystroke on measured corpora; failure entries never retained;
arena-free terminal entries only. Honest ceiling identified: the
structural re-walk.

## Target (tree-sitter's bar)

1. **Structure-sharing splice**: persistent AST + right-spine rebuild —
   an edit invalidates only the spine from the change point; untouched
   subtrees are shared, not re-walked. The specced item 9.
2. **Error-tolerant edits**: recovery mode (1-error-recovery R1/R2)
   composes with incremental — a document with errors still parses
   incrementally (tree-sitter's defining property).
3. **Sub-millisecond keystrokes on large documents**: the acceptance
   number, measured on the expressir giants with real edit sequences.

## Acceptance

- Tree-equality gates: incremental result == full reparse result (the
  existing 30-edit sequences gate, extended to thousands of edits and
  multi-region edits).
- Keystroke benchmark published in BENCHMARKS.md (2-sota-benchmarks).
- Memory bounded: sharing must not pin the whole document history
  (generation GC for stale generations).
