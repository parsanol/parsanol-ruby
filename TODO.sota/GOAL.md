# Goal prompt (paste into a fresh session to drive the whole roadmap)

MISSION: drive parsanol to SOTA — complete every task in TODO.sota/ in tier order, with proof. Read TODO.sota/0-README.md first (vision, tiers, execution laws); CLAUDE.md and your memory carry the standing laws.

System: ~/src/parsanol — parsanol-ruby (gem: Ruby interpreter + VM, PARG compiler/artifacts, LSP), parsanol-rs (Rust: portable packrat + VM engines, corpus/), parsanol-ts (npm: wasm runtime). parslet semantics are the contract; PARG artifacts (checksummed, provenance-stamped) the distribution; cross-engine conformance enforced, never promised.

DONE requires ALL of:
- Both engines in lockstep (rs portable+VM → ruby interpreter+VM → wasm re-vendored via scripts/refresh-wasm.sh → ts tests). Never one engine ahead.
- Conformance corpus cases pinning the behavior, same PR (rs CI gates corpus changes; cite docs/parg-semantics.md rules once task 3 lands).
- Specs with real objects (never doubles); guide/docs updated; TODO Status flipped with PR links and honest results.
- Full CI per repo (ruby 24-leg; rs incl. MSRV 1.86), merged in dependency order: rs → ruby → wasm/ts → releases.
- Releases via the trains: ruby = dispatch Release, bump_type patch/minor (auto-merged bump PR, then tag/build/smoke/publish; skip publishes current main; the shipped-audit auto-fires — confirm green); rs = release-plz; ts = package.json bump PR + dispatch. Verify platforms, tag, GitHub release.
- Issues closed with resolution comments; deferrals filed as issues with recommendations.

THE WORK (acceptance criteria in each file):
1. 1-error-recovery.md — best-effort partial trees + cause-tree annotations, zero success-path cost; then resync recovery. Flagship.
2. 2-sota-benchmarks.md — published suite vs pest/tree-sitter/Lark on shared corpora; interleaved A/B with GC.start, median-of-N, no tiny-input ratios; BENCHMARKS.md + ci_gate extension.
3. 3-parg-formal-spec.md — docs/parg-semantics.md: small-step semantics + corpus coverage matrix (cases ↔ rules).
4. 4-lsp-playground.md — LSP hover/go-to-def/completion/semantic tokens; wasm playground on the Astro site.
5. 5-left-recursion.md — OWNER GATE (deliberate parslet extension): ask first; MVP = ANTLR-style compile-time rewrite.
6. 6-compact-packrat.md — formalize bounds; spill tier for giants; ship only on measured wins.
7. 7-incremental-treesitter-grade.md — structure-sharing splice; error-tolerant edits (composes with 1); sub-ms keystrokes; == full-reparse gates.
8. 8-fuzzing-and-verified-core.md — proptest random-grammar cross-engine differential (nightly); then verified-core scoping.

HARD RULES: everything through PRs with green required checks — main is protected and verified. Never bump versions or requirements/floors yourself — owner decisions; ask. MSRV 1.86; sha2/proptest pins deliberate. Never ship engines out of lockstep. Perf claims only from interleaved same-condition A/B. User checkouts are sacred: worktrees, verify every hunk. Corpus + guide + docs land with every behavior change. Blocked on an owner decision? File it with a recommendation, move to the next unblocked task, keep going — do not stop.

FINISH: all TODO.sota files closed with results; everything released and audited on all three registries; docs/spec/guide current; org at 0 open; final STATUS report (shipped / deferred + why). Report progress per task.
