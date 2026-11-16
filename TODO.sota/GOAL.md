# Goal prompt -- SOTA 2027 (paste into a fresh session)

MISSION: drive TODO.sota (this ledger) + TODO.perf (parsanol-rs) to zero open nodes with parsanol the measured industry SOTA: one checksummed artifact, byte-identical trees everywhere, PUBLISHED numbers beating tree-sitter -- throughput, recovery, incremental. Receipts (rs#533): 1.073 us/B vs 0.029; diagnostics won, suffix lost 14.9% vs 70.6%; incremental 0.93x vs 34-57x. Close the gaps -- fully.

ORDER (each Gate is the Definition of Done):
1. THROUGHPUT = TODO.perf/10-13. Phase 0: profile; kill the success-path ErrorTracker cost (every failed alternative tracks); LTO builds; --no-ast split; pooled tree writes. Phase 1: compile-time FIRST sets; disjoint Choices emit Switch tables; Scan for class runs. Phase 2: LR/native codegen for the deterministic subset, PEG VM fallback. Projection 0.15 -> 0.03 us/B on JSON; then beat 0.029.
2. REGISTRY (TODO.sota/10): move json/csv/ini out of pubid-grammar (identifier-only, owner directive) into parsanol/grammars, gate stack ported; CI pin is the owner's call; add TOML + lua.
3. RECOVERY (TODO.sota/1): declare envelopes on the json flavor (engine shipped); re-run the 60-case harness; suffix >70%, keep the diagnostic win; add the TED scorer.
4. INCREMENTAL (TODO.perf/9): innermost-container splice retention (reused 0/200; rs#258); fixed-cost cuts; >10x own-fresh, identity 400/400.
5. #530 constrained decoding. 6. #529 PARG LSP. 7. #532 adoption kit (gated on tables).

LAWS: PRs only -- never main or tags; stage explicit paths; never delete sources; rebase before every push; PR bodies via files; no AI attribution; releases ship all runtimes together, versions are the owner's call; cargo test under the RSS watchdog; perf keeps corpus + cross-runtime gates byte-identical; losses publish with profiles; blocked -> file with a recommendation, move on.

PROOF per node: Gate green on every runtime; receipts in benchmarks/sota/results/ + docs/BENCHMARKS.md; ledgers updated in the same PR.

FINISH: zero open nodes; docs/BENCHMARKS.md shows parsanol ahead of tree-sitter on throughput, recovery, incremental; final STATUS report (shipped / deferred + why).
