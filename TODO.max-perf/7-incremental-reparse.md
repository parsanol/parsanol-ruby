# 7. Incremental reparsing (P2)

## Why

Editor-integration consumers re-parse on every keystroke. The research
consensus (tree-sitter "parse on every keystroke", gpeg's incremental
packrat) is that reusing the previous parse's stable regions — instead
of re-parsing the whole document — is what makes parsing feel instant.

## Design sketch

- parsanol-rs already exposes prefix-mode parsing and an incremental
  module; the missing piece is invalidation by edit span: only
  (position, atom) memo entries at or after the edit, plus rule
  spans crossing it, are invalidated.
- The bytecode VM's explicit state makes this natural: a reusable
  program plus a persisted memo/index from the previous parse, keyed
  by content hash.
- Wire through the FFI as `parse_incremental(handle, input, prev)`.

## Acceptance gates

- Differential: incremental results identical to full re-parses on the
  SRL corpus with simulated edit sequences.
- Perf: keystroke-class re-parses < 5 ms on 600 KB documents.

## Status

Shipped as parsanol-rs TODO.perf items 4+8 (IncrementalSession,
snapshot-tier retention, latency bench); see 0-index.md.
