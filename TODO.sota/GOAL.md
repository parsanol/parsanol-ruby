# Goal prompt -- beyond-SOTA, fully (paste into a fresh session)

MISSION: finish TODO.sota/9's completion map -- PARG replaces ABNF for specification and ANTLR for parser generation: one checksummed artifact, byte-identical trees on every engine (ruby, rs, wasm, ts, C/C++, python), compile-time-validated typed bindings, unicode-native matching, published fast numbers, and the two uncharted frontiers (constrained decoding; measured recovery) occupied. Read TODO.sota/0-README.md and 9-language-evolution.md first; memory + CLAUDE.md carry the standing laws.

Work the map's nodes in critical-path order (each Gate is the Definition of Done):
1. A1-A3: rs#305 consume-all at the ffi program layer (vm_path_spec is the red pin); CI cache-version bump + parity-failure diff; selfhost/pubid-grammar brace refresh.
2. B parallel C: modern capture (owner picks the mode name first), bindings v2 (paths, validation, typed emission, 3-runtime parity), ABNF/ANTLR corpus tails, lint completion; U2 folding + U3 categories; C1 char columns only after the owner approves the wire re-bake.
3. E1 the PARG frontend in Rust (rs#298) -- the keystone: lexer, parser, compiler, byte-parity with the Ruby compiler on the source corpus; drift = release blocker for both. Then E2 wasm live compilation; E3/E4 after owner unblocks.
4. D: quiet-host benchmark publication; codegen in-process bench; incremental research.
5. F: #321 constrained-decoding export (acceptance-equivalence corpus, resync-driven masks); rs#304 recovery metrics (seeded, engine-identical, published, no-regression); verified core per its scoping doc.

LAWS: PRs only -- never push main or tags; stage explicit paths; never delete sources; worktrees (absolute paths), verify the branch before every commit; envelope state is a wire contract (advisory lints stay out); versions/requirements via trains only; PR/issue text via body files; no AI attribution; corpus + guide land with every behavior change; cargo test under the RSS watchdog; numbers only from a quiet host; blocked on an owner decision -> file it with a recommendation, move on, keep going.

PROOF per node: tests + differential corpus green on every engine, the named Gate green, the honest gap stated, TODO.sota + docs updated in the same PR.

FINISH: no open map nodes; registries current and audited; specs/guide/site current; final STATUS report (shipped / deferred + why).
