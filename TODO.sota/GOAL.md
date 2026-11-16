# Goal prompt -- SOTA 2027, complete (paste into a fresh session)

MISSION: close every open node in TODO.sota (this ledger) and TODO.perf (parsanol-rs) until parsanol is the measured industry SOTA: one checksummed artifact, byte-identical trees on every runtime (rs, ruby, py, ts, wasm), and PUBLISHED numbers beating tree-sitter on the shared corpora -- throughput, recovery diagnostics, keystroke incremental. Receipts are landed (rs#533, #526 closed): throughput 1.073 us/B vs tree-sitter 0.029; recovery diagnostics won, suffix recovery lost 14.9% vs 70.6%; incremental correct but 0.93x vs 34-57x. Close the gaps -- fully.

ORDER (each node's Gate is the Definition of Done):
1. THROUGHPUT = TODO.perf/10-13. Phase 0: profile doc1; kill the success-path ErrorTracker cost (every failed alternative tracks today); bench builds at LTO + codegen-units=1; --no-ast recognition split; pooled tree writes. Phase 1: compile-time FIRST sets; first-set-disjoint Choices emit Switch tables; Scan instruction for class runs (extends 2/6). Phase 2: LR-table/native codegen for the deterministic subset, PEG VM the fallback. Projection 0.15 -> 0.03 us/B on JSON; then beat 0.029.
2. REGISTRY (TODO.sota/10): move json/csv/ini OUT of pubid-grammar (identifier-only, owner directive) into parsanol/grammars with the gate stack ported; pubid-grammar's CI pin is the owner's call; add TOML + lua-subset.
3. RECOVERY (TODO.sota/1): declare skip/resume envelopes on the json flavor (engine support shipped); re-run the 60-case harness; target suffix >70% while keeping the diagnostic win; add the TED scorer.
4. INCREMENTAL (TODO.perf/9): innermost-container splice retention (reused 0/200 on JSON; the rs#258 collapse); per-step fixed-cost cuts; target >10x own-fresh, identity 400/400.
5. #530 constrained decoding (mask compilation off terminal_vocabulary, no-dead-end demo). 6. #529 PARG LSP, self-hosting dogfood. 7. #532 adoption kit (gated on published tables).

LAWS: PRs only -- never main or tags; stage explicit paths; never delete sources; fetch+rebase before every push (parallel owner work); PR bodies via files; no AI attribution; releases ship all runtimes together via trains, versions are the owner's call; cargo test under the RSS watchdog; every perf step keeps the corpus + cross-runtime gates byte-identical; losses publish with profiles; blocked -> file it with a recommendation, move on.

PROOF per node: the named Gate green on every runtime; receipts updated in benchmarks/sota/results/ + docs/BENCHMARKS.md; TODO ledgers updated in the same PR.

FINISH: no open nodes in TODO.sota or TODO.perf; docs/BENCHMARKS.md shows parsanol ahead of tree-sitter on throughput, recovery diagnostics, and incremental; final STATUS report (shipped / deferred + why).
