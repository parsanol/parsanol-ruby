# 7 — Incremental parsing to tree-sitter grade

Status: open — Tier 2. Extends TODO.max-perf/9 (prefix-tree reuse,
splice). The engine work lives in parsanol-rs; the session API is
shared with Ruby.

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
