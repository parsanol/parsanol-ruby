# 6. Pure-Ruby engine posture (P2)

## Why

The pure-Ruby interpreter remains 0.6–0.8x parslet on
heavy-backtracking grammars (documented honestly in TODO.perf/10
item 3). Since the native tier now handles every mode with no Ruby
fallback (TODO.perf/8 complete), the Ruby engine's role is exactly
one: environments without a usable native extension (no prebuilt
platform gem, no Rust toolchain, non-MRI rubies without the ffi gem).

## Decision

- Do NOT chase the algorithmic gap in the Ruby interpreter: every
  remaining lever there is per-step cost, and the same engineering
  spent on the Rust VM (TODO.max-perf/4) yields strictly more.
- Keep the Ruby engine as the semantic reference implementation
  (parslet-parity oracle) — its correctness duties grow, its
  performance duties shrink.
- Document the posture in the README performance section: native is
  the default and the fast path; `mode: :ruby` is the portability and
  reference path.

## Acceptance gates

- README/README.adoc performance section states engine roles and the
  native-by-default behavior.
- No behavior change; specs green.

## Status

Done this round (docs).
