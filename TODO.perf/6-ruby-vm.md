# 6 — Ruby bytecode VM (the path to ≥5x vs parslet)

Status: IMPLEMENTED + validated (2026-09-15); heavy-backtracking
grammars still need VM memoization (see "Gap analysis")

## Mandate

The pure-Ruby path must be **at least 5x faster than parslet**. The tree
interpreter (one method dispatch per atom application, one `[true, value]`
tuple + one Slice per terminal) tops out around 1.9x. Getting to 5x
requires removing the per-atom interpretation itself, not trimming it.

## Design

Compile the atom tree once into a flat stride-4 integer program and execute
it with a tight `while`/`case` loop — no method dispatch per atom, zero
allocations for terminals (matched spans are packed Integers
`(pos << 20) | len`, immediate values, GC-free).

### Opcodes

| op | meaning |
|----|---------|
| `STR lit_bytes len` | byte-compare literal at pos |
| `RE re table` | anchored `re.match?(input, pos)`; ASCII byte table fast path |
| `ANY` | advance one char (lead-byte width table for multibyte) |
| `SEQ_BEGIN/END` | build `[:sequence, *values]` like `Sequence#try` |
| `CHOICE alt_pc` / `POPBT` | ordered choice; commit on branch success |
| `REP_TEST/STEP/EXIT` | repetition with min/max + tag (`:repetition`/`:maybe`) |
| `NAME_END name` | defer `Named`'s eager `{name => flatten(v, true)}` to materialization |
| `CALL sub / RET` | Entity rules as subroutines (explicit call stack, no Ruby recursion) |
| `LOOK_POS/NEG ...` | lookaheads with position restore |
| `DROP` | Ignored: keep match, discard value |
| `FAIL / HALT` | unwind backtrack stack / accept |

### Semantics that must stay byte-identical

- Value encodings: `[:sequence, ...]`, `[:repetition, ...]`, `[:maybe, v]`,
  `[:maybe]`, `{name => flatten(inner, named=true)}` (Named flattens
  eagerly during parsing — the VM defers it to a bottom-up materialization
  pass that produces the same tree).
- Terminals are Slices created lazily via `input.byteslice(pos, len)`.
- `Re`/`Any`/single-char `Str` consume ONE CHARACTER (not one byte);
  byte-based matching must advance by char width.
- `consume_all` is propagated statically (last element of sequences,
  through alternatives/named/lookahead; repetition bodies always get
  `false`). A repetition that is a `consume_all` site fails on trailing
  input, exactly like `Repetition#try_general`'s "Extra input" check.
- Ordered choice never retries later alternatives after one succeeds.
- No zero-width repetition guard — mirror the interpreter (and parslet).

### Execution model

- `input.unpack("C*")` once; all terminal matching is byte indexing.
- Backtrack stack entries `[pc, pos, rlen, cbase, kind]`; `rlen` truncation
  of the result stack gives transactional rollback; `kind` distinguishes
  ALT / REP-BODY / LOOK entries (REP-BODY with `count < min` re-fails).
- Repetition counters live in a flat frame stack, not objects.
- Guards: step budget (`200 * n + 10_000`) and call-depth cap; on breach,
  bail to the interpreter (cold path, preserves behavior for pathological
  grammars).
- Errors: on VM root failure, run the existing interpreter double-parse for
  cause-tree diagnostics — failures are cold, messages stay byte-identical.

### Unsupported atoms → interpreter fallback

`Dynamic`, `Capture`, `Scope`, `Cut`, `Custom`, `Infix`, anything unknown.
Also `prefix: true` parses (rare).

### Compile cache

Programs cached by root atom `object_id` (same risk profile as
`GRAMMAR_HASH_CACHE`); atoms are effectively immutable after construction.

## Expected result

Interpreter spends ~10 method calls + 2 allocations per terminal; the VM
spends ~5 non-allocating loop iterations. Combined with removing GC pressure
(GC was 50–65% of interpreter wall time), target is 3–6x over the current
1.8–1.9x interpreter ⇒ **5–10x vs parslet**.

## Files

- `lib/parsanol/vm.rb` — compiler + executor + materializer
- hook in `Parsanol::Atoms::Base#parse` (String input, no `prefix`)

## Implementation record (2026-09-15)

`lib/parsanol/vm.rb` is complete: compiler (terminal fusions, leaf-entity
inlining, non-recursive rule inlining, MAX_PROGRAM=40k guard), executor
(stride-6 backtrack entries incl. call-stack length, BAIL sentinel, step
budget `200n+10k`), and materializer (packed-span Integers → Slices,
deferred Named flattening, `Mat` extends CanFlatten). Hook lives in
`Parsanol::Atoms::Base#parse` (String + must-consume-all only).

Bugs found and fixed while validating (keep these in mind when touching
the compiler):

1. **Missing POPBT** — every successful non-last alternative branch leaked
   its CHOICE backtrack entry; stale entries then hijacked later unwinds.
   Fix: emit POPBT before the JMP in compile_alternative.
2. **Unanchored regex** — `Regexp#match?(str, pos)` searches FORWARD.
   The VM matched a space via digits much later in the input. Fix: use a
   StringScanner (anchored) for the general regex path.
3. **HALT after subroutines** — root CALL return address collided with the
   first subroutine's entry. Fix: emit HALT before appending subroutines.
4. **Calls not rolled back on backtracking** — the calls stack is now the
   6th backtrack slot (`calls.slice!` in unwind).
5. **Stale entries above the popped entry** — unwind truncates
   `bt.slice!(blen..)`.
6. **BAIL vs clean failure** — internal bail (disable VM for the grammar,
   fall through to interpreter) is distinct from `[false, nil]` (the input
   does not parse; interpreter reparse produces the cause tree). A clean
   failure must NOT disable the VM.
7. **:heavy ratio heuristic** — per-input-size ratios flapped; the disable
   signal is now an absolute step density (`steps > (n<<9)+1000`).

Validation: 1187 gem specs green; differential tests (calc/json/molecule/
parens grammars) ALL IDENTICAL across interpreter/VM/native.

## Real-workload gap analysis (2026-09-15)

On linear/token grammars the VM delivers (molecule: ~10 steps/byte, healthy)
and the pure-Ruby path beats parslet 1.7–1.9x. On the two REAL parslet
consumers tested (`~/src/asciichem`, `~/src/pubid`) the picture inverts:

| workload | parslet | parsanol ruby | parsanol native |
|---|---|---|---|
| molecule bench (large) | 2.08s | 1.25s (1.7x) | 0.19s (10.9x) |
| asciichem grammar | 1.95s | 3.48s (0.56x) | 1.21s (1.6x) |
| pubid ISO fixtures | 0.25s | 0.42s (0.6x) | 0.11s (2.3x) |

Both real grammars are heavy-backtracking; the VM correctly self-disables
via the `:heavy` signal, and the interpreter is GC-bound there (69% GC in
the asciichem profile — the `[true, value]` tuple + per-char Slice churn).

Native now parses both real grammars correctly and 1.6–2.3x faster than
parslet (after the fixes below), and is the default engine — so users get
parslet-beating performance out of the box on these workloads today.

## Next steps (in order of leverage)

1. **VM memoization for heavy grammars** — a packrat table keyed
   `(pc, pos)` consulted only after the step budget signals heavy
   backtracking (two-phase: run naive, memoize on retry). Would convert
   the 0.56–0.6x cases to VM speed (expected ≥2x vs parslet) without
   taxing the linear-grammar fast path. The executor's frames/bt layout
   already has the information needed (subroutine pc = rule identity).
2. **Allocation diet for the interpreter fallback path** — reuse a
   preallocated result-stack array; only materialize Slices for named
   captures (unnamed string runs are already joined single-Slice).
3. **Root-level incomplete-consumption in native** — the Ruby engine
   threads `consume_all` into every alternative branch (a branch that
   leaves input unconsumed FAILS and the next branch is tried); the Rust
   engine only checks completeness once after the root match and errors
   "Parse incomplete" instead of backtracking. Synthetic grammars like
   `prefix | full_match` diverge (native errors, Ruby succeeds). Real
   grammars hit this only as native-failure → Ruby-fallback (correct but
   2x cost). Fix by threading a consume_all flag through try_atom the way
   sequences pass it to their last child.

## Cold-start round (2026-09-24)

The reported "VM cold-start superlinear slowdown" on repeat+maybe
grammars turned out to be a **broken FAIL dispatch**, not a
memoization-activation gap:

- ab1a17b ("FAIL dispatches through the case table") replaced the
  `if pc == FAIL` register check with `case ops[pc]; when FAIL`. The FAIL
  sentinel lives in the pc register, not in program memory: a failing
  terminal sets pc = 17 and the next dispatch read whatever operand sat
  at slot 17. It missed every branch, hit the `else` catch-all, returned
  BAIL, and sticky-disabled the VM for the grammar.
- Consequence: any parse whose control flow includes a terminal failure —
  which is how every repetition ends — silently ran the interpreter
  instead. Suites stayed green (BAIL→interpreter is semantically
  transparent); the cost was performance-only. A KV repeat+maybe grammar
  measured 4.0s at 100 pairs / 29.6s at 800 pairs pre-fix (interpreter
  probe work), vs ~12ms at 200 pairs post-fix (VM, linear).
- Fix: the compiler appends a dedicated `[FAIL, nil, nil, nil]`
  instruction after HALT and the subroutines; the executor derives
  `fail_pc = ops.size - 4` and every `pc = FAIL` site jumps there, so
  `when FAIL` is a true dispatch target. The per-step comparison the
  original commit saved stays saved. Regression spec:
  `spec/parsanol/vm_fail_dispatch_spec.rb`.

Structure-seeded memoization (compile-time repeat/maybe analysis →
`@heavy` pre-seed, memoize from step 0, recomputed per compile so fresh
parser instances get it too): implemented as mandated. Honest A/B
(min-of-9, GC.start): **neutral post-Fix-A** on valid and failing
inputs, inline and subroutine-tier grammars alike — the naive pass is
already linear once the VM stays enabled; the seed neither helped nor
hurt (linear_kv 6.0ms, expr_subr 37ms, unchanged). Kept as insurance for
grammars whose naive pass would bust `200n+10k` before the memoized
retry; the TODO.perf/7-style dense-memo regression does not appear at
CALL-site granularity. Lowering thresholds as the alternative approach:
interpreter `BACKTRACK_ACTIVATION_LIMIT` 64→16→1 measured no consistent
gain (1 was worse); the VM density threshold is moot with seeding.

Follow-up finding (out of scope, flagged): neither engine guards
zero-width repetition loops. `(str("(") >> expr >> str(")")).maybe`
matched empty loops the VM into its step budget and then BAILs to an
interpreter that has NO guard at all — an unbounded hang (paren
grammar, depth 10 = minutes of CPU). A progress guard mirroring
documented acceptance would make both engines terminate; needs its own
round with a parity decision.
