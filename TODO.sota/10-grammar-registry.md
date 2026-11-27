# 10 — The grammar registry: where general-purpose flavors live

**Owner directive (2026-11-16): pubid-grammar is the
publication-identifier grammar repo — identifier flavors only.**
Data-format grammars do not belong there. The json flavor's presence
(merged 82afe2a) and the csv/ini PR (#128, held open) were misplaced;
this item re-homes them.

## The work

1. Create `parsanol/grammars` as the general-purpose flavor registry:
   gate stack ported (contracts regen, frozen corpora, cross-runtime
   check, dashboard).
2. Move json, csv, ini out of pubid-grammar: revert the json commit
   (owner go-ahead — it is their merged commit), close #128, land all
   three flavors in the new registry sealed at the current train.
3. pubid-grammar's red CI (grammar job failing since the json commit:
   contracts sealed at gem 1.5.1 vs the CI pin `PARSANOL_VERSION:
   1.3.126`) is the owner's pin decision — surfaced on #128 with both
   options; do not bump the fleet pin unbidden.
4. Next flavors: TOML, then a lua-subset (the #531 breadth program),
   each with the full gate stack in the new registry.

## Gate

pubid-grammar main green again (identifier flavors only); all three
data-format flavors live in `parsanol/grammars` with corpus +
cross-runtime gates green; the rs#526 JSON suite consumes the
registry's json artifact.

## Status (2026-11-27): the re-homing LANDED

- **parsanol/grammars created** (public): json, csv, ini, toml, lua
  moved in with the gate stack (per-grammar compile+tests, the
  corpus/artifact checksum freeze, the rust VM replay, the wasm
  replay), sealed at the 1.5.26 train.
- **pubid-grammar#156 merged**: main is identifier flavors only (56
  grammars); the grammar job GREEN again — the red dated from the
  json commit's presence and cleared with the removal.
- pubid-grammar's stale flavor worktrees/branches triaged and
  cleaned (all superseded by landed commits).
- **The open formality**: the rs#526 JSON suite's pinned
  `benchmarks/sota/json-artifact.json` predates the registry seal;
  swapping it to the registry's `artifacts/json.json` changes the
  benchmark workload pin, so the swap rides the quiet-machine
  receipt re-bake (the comparability law: the artifact swap and the
  perf re-bake land together).
