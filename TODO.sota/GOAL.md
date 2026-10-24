# Goal prompt -- beyond-SOTA, fully (paste into a fresh session)

MISSION: finish TODO.sota/9's completion map -- PARG replaces ABNF for specification and ANTLR for parser generation: one checksummed artifact, byte-identical trees on every engine (ruby, rs, wasm, ts, C/C++, python), compile-time-validated typed bindings, unicode-native matching, published fast numbers, and the two uncharted frontiers (constrained decoding; measured recovery) occupied. Read 0-README.md and 9-language-evolution.md first; memory + CLAUDE.md carry the standing laws.

Critical-path order (each node's Gate is the Definition of Done):
1. A1-A3: rs#305 consume-all at the ffi program layer (vm_path_spec is the red pin); CI cache-version bump + parity-failure diff; selfhost brace refresh.
2. B parallel C: modern capture (owner picks the mode name), bindings v2 (paths, validation, typed emission, 3-runtime parity), ABNF/ANTLR corpus tails, lint completion; U2+U3; C1 char columns only after the owner approves the wire re-bake.
3. E1 the PARG frontend in Rust (rs#298) -- the keystone: lexer, parser, compiler, byte-parity with the Ruby compiler on the source corpus. Then E2 wasm live compilation; E3/E4 after owner unblocks.
4. D: quiet-host benchmarks; codegen in-process bench; incremental research.
5. F: #321 constrained-decoding export; rs#304 recovery metrics; verified core.

LAWS: PRs only -- never push main or tags; stage explicit paths; never delete sources; worktrees, verify the branch before every commit; envelope state is a wire contract (advisory lints stay out); versions via trains only; PR/issue text via body files; no AI attribution; corpus + guide land with behavior changes; cargo test under the RSS watchdog; numbers only from a quiet host; blocked on an owner decision -> file it with a recommendation, move on, keep going.

PROOF per node: tests + differential corpus green on every engine, the named Gate green, the honest gap stated, TODO.sota + docs updated in the same PR.

FINISH: no open map nodes; registries current and audited; final STATUS report (shipped / deferred + why).
