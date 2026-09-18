# 8. Compiled-program artifact cache (P2)

## Why

XGrammar-2's Cross-Grammar Cache — substructure-level reuse across
grammars — reports 6x faster compilation. Our analogue: persist the
compiled `Program` (and the packrat engine's derived analysis) so a
process's first large parse skips registration-time compilation, and
processes sharing a grammar share the artifact.

## Design sketch

- Program serialization: instructions + string/regex/charset pools to
  a stable binary format (`Program::to_bytes` exists for the wasm
  tier's benefit — verify round-trip).
- Cache keyed by grammar structure hash (the Ruby side already
  computes one for handle caching); stored under an XDG cache dir with
  the same integrity discipline expressir's Marshal cache uses
  (content-hash validation, corrupt artifacts fall back to compile).
- Cross-grammar substructure reuse (XGrammar-2's actual contribution)
  applies to the SUBROUTINE level: hash rule bodies and dedupe
  identical bodies across grammars within a process.

## Acceptance gates

- Round-trip: compiled-from-cache parses byte-identically to
  compiled-fresh on the SRL corpus.
- Cold-start: first large parse drops the registration compile cost.

## Status

Backlog — after TODO.max-perf/4 phase 4.
