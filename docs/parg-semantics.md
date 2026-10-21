# PARG — normative semantics

*Version 1.0. This document is normative. The language guide
([parg-language-guide.md](parg-language-guide.md)) is the friendly edition; where
the two disagree, this document and the conformance corpus win.*

PARG is a PEG language. This document defines, per construct, the **match
relation** (position and value), the **capture semantics**, the **failure
semantics**, and the **diagnostics obligation** every engine must satisfy. Rules
are numbered (`T1`, `C3`, `S2`, …) so corpus cases and reviews can cite them.

Every engine that consumes a `parsanol-tree/v2` artifact — the Ruby
interpreter, the Ruby bytecode VM, the Rust portable engine, its bytecode VM,
the wasm build, the TypeScript runtime — MUST implement these rules. Where
this document and an engine disagree, the engine is wrong.

Conformance is enforced by the corpus in `parsanol-rs/corpus/conformance`
(WPT rule: a behavior change lands with its corpus change in the same commit).
Every rule below cites the case that pins it, or is listed as a corpus gap in
[Coverage gaps](#coverage-gaps) (parsanol-rs#254).

---

## 1. Notation and foundations

### M1 — Input, positions, determinism

Input is a byte string `w`, interpreted as UTF-8 text. Positions are **byte
offsets** `0 ≤ p ≤ |w|`. `ANY` and character classes match one Unicode scalar
value; `%x` classes denote code points; literals match their UTF-8 byte
sequence. Reported offsets (`error.offset`, `consumed_upto`) are byte offsets.

PEG matching is deterministic: for a fixed grammar and input, exactly one
outcome exists at every position. There is no ambiguity to report and no
backtracking strategy to choose.

*Pins: every case; offsets are asserted by the recovery specs.*

### M2 — Match relation

```
(r, w, p) ⇓ (p′, v)      r succeeds: consumes w[p, p′), yields value v
(r, w, p) ⇓ ⊥(q, E)      r fails: deepest real-content failure at q, expected E
```

`v` is an abstract value (§2). Captures are part of `v`; the judgment is pure.
An engine MAY keep captures in a mutable store, but observable results MUST be
indistinguishable from this pure relation.

### M3 — Transactional matching

A failed attempt has no effect: the position stays at `p` and no capture or
value produced inside it survives. This is a semantic law, not an
implementation detail — ordered choice (C2), optional (C4), repetition
termination (C3) and lookahead (C5) all depend on it. Engine-internal
recovery journals (E2) are the one sanctioned exception: they are explicitly a
best-effort superset and are not part of the match relation.

*Pins: `lookahead`, `rejects`, `skip_trivia` (failed later branches never
contribute captures to examples).*

### M0 — Entry and full consumption

`parse(entry, w)` runs the entry's root rule at position 0 and succeeds only
if the root succeeds **and** consumes all of `w`. Leftover input is a failure
(‖ an unconsumed-input diagnostic at the root's end position).

A grammar may declare several entries over one rule set. Each entry has its
own root, portable grammar, and bindings; `parse` and `parse_and_bind` are
per-entry. In-file tests name their entry when the grammar declares more than
one (A1–A3); the artifact bakes the resolved entry into every test.

If the grammar declares `skip` (S1), a non-atomic entry root is wrapped as
`skip? root skip?`, so leading and trailing trivia are consumed before the
full-consumption check (S5). An atomic entry root receives no wrapper (C8).

*Pins: `short_rep` (`"abcd"` rejected although `1*3` matches a prefix),
`repetition` (`"abc"`).*

---

## 2. Values

### V0 — Value domain

A value is one of:

| Form | Produced by |
|---|---|
| `ε` (nil) | lookaheads, injected trivia, an absent optional inside a capture |
| **text** `t` | terminals, concatenations of text |
| **map** `{k₁: v₁, …}` | named captures, merged capture maps |
| **seq/rep/maybe** `[v₁, …, vₙ]` | sequences, repetitions, optionals (tagged internally) |

Text may be represented as a string or as a slice (text + span). The abstract
value is the text; engines must not expose representation differences through
any conformance surface (A2, A3, E3).

### V1 — Flattening: sequences

`flatten` reduces the tagged value tree to the consumer tree. For a sequence,
children are flattened left to right and merged; `ε` is neutral and skipped.
With `⊕` the pointwise merge:

```
ε ⊕ x = x ⊕ ε = x
H₁ ⊕ H₂ = H₁ ⊎ H₂            maps merge; the right value wins on a duplicate key
T₁ ⊕ T₂ = T₁·T₂              text concatenates
T ⊕ X = X ⊕ T = X            text next to a non-text value is dropped
H ⊕ X = [H, X]               X is neither map nor text: array in source order
X ⊕ H = [X, H]
A₁ ⊕ A₂ = A₁ ++ A₂           arrays concatenate
```

An empty sequence flattens to the empty text `""`.

*Pins: `atoms_lexical`, `merge_laws`, `merge_array`.*

### V2 — Flattening: optional

`[ x ]` flattens to `flatten(x)` when it matched. When it did not match:
`ε` if the optional is inside a capture, empty text `""` otherwise.

*Pins: `repetition` (`dashed` on `"ab"` omits `dash`), `optional_capture`
(`dash: null` when absent).*

### V3 — Flattening: repetition

Flatten each iteration, then:

1. if any iteration is a **map**, keep exactly the map iterations and drop
   every non-map iteration;
2. otherwise, if any iteration is an **array**, concatenate all array
   iterations and drop every non-array iteration;
3. otherwise, if the repetition is inside a capture and is empty, yield `[]`;
4. otherwise concatenate the text iterations (`ε` skipped; all-`ε` → `""`).

This is parslet's `CanFlatten` behavior, including its data loss; it is a
compatibility contract, not a recommendation (parsanol-ruby#231). The stable
idiom is to capture every structural iteration so rule 1 applies uniformly.

*Pins: `repetition`, `short_rep`, `repeat_flatten` (mixed iterations).*

### V4 — Named captures

`x as name` (K1) yields the map `{name: flatten(x)}` — note the capture's
inner flattening uses the *named* variant of V2/V3. Rule references are
transparent: capturing a rule captures what the rule produced.

---

## 3. Terminals

### T1 — Literal `"s"`

`("s", w, p) ⇓ (p + |s|, s)` iff `w[p, p+|s|) = s`; otherwise `⊥(p)`. A
non-empty literal never matches empty input. The empty literal is rejected at
compile time (X4) except as the zero-width marker (T6).

*Pins: `atoms_lexical`, `lookahead`, `repetition`, `skip_trivia`.*

### T2 — Case-insensitive literal `%i"s"`

Matches iff the next code units compare case-insensitively to `s`; consumed
text is the **input spelling**, not the pattern spelling. The value is the
consumed text. Engines implement this with their regex engine's Unicode-aware
`(?i:)` semantics; non-ASCII folding parity is pinned by
`casefold_nonascii`.

*Pins: `casefold`, `casefold_nonascii`.*

### T3 — Character class `%xNN`, `%xNN-MM`

Consumes exactly one code point whose value is in the specified range set and
yields that text. At end of input: failure. A class is never satisfied by more
than one character; `ANY` is the full range `U+0000–U+10FFFF`.

*Pins: `atoms_lexical`, `lookbehind`, `nesting`, `rejects`, `skip_trivia`.*

### T4 — Byte sequence `%x0D.0A`

Consumes the sequence of specified code points, one per element, yielding the
consumed text. It is a fixed-length terminal, not a repetition.

*Pins: `byte_sequence`.*

### T5 — `ANY`

Consumes one code point (T3 with the full range).

*Pins: `lookbehind`, `rejects`.*

### T6 — Zero-width marker `"" as name`

The empty literal is only expressible directly under a capture. It consumes
nothing and succeeds unconditionally; the capture records presence as
`{name: ""}` (zero-length text). It exists for presence flags; it is the only
zero-width primitive besides lookahead.

*Pins: gap G2.*

---

## 4. Combinators

### C1 — Sequence `x y`

Evaluate left to right from `p`; the value is the merge (V1) of the children's
flattened values. If a child fails, the whole sequence fails at that child's
failure position and the position resets to `p` (M3).

*Pins: `atoms_lexical`, `lookahead`, `nesting`, `repetition`, `skip_trivia`.*

### C2 — Ordered choice `x / y`

Evaluate arms in source order from `p`. The first success wins; no later arm is
attempted. If all arms fail, the choice fails; the reported deepest position is
the maximum over the arms (diagnostics, §7). Choice is committed: a success
that leaves the rest of the enclosing sequence unsatisfiable does **not**
retry a later arm (PEG, not regex alternation).

*Pins: `lookbehind`, `nesting` (`emph / other`), `skip_trivia`.*

### C3 — Repetition `*x`, `1*x`, `m*n x`

Greedy, bounded by `min` (default 0) and `max` (default unbounded):

```
n = 0; q = p
while max is unbounded or n < max:
    if (x, w, q) ⇓ (q′, v):
        n += 1; keep v
        if q′ = q: break            # zero-width iteration counts once, then stops
        q = q′
    else: break
if n < min: ⊥(p)                     # position resets; no iterations survive
else: (q, [v₁ … vₙ])
```

A terminating failure of the body is normal end-of-repetition, not a failure of
the repetition. It never contributes captures. An iteration that consumes
nothing is counted once and then terminates the loop — repetition never hangs.

*Pins: `repetition` (2*2), `short_rep` (1*3), `rejects` (0*),
`atoms_lexical` (1*).*

### C4 — Optional `[ x ]`

Equivalent to `Repetition(x, 0, 1, :maybe)` (C3): one attempt at `p`; on
success its value, on failure `ε` with position `p` and no captures (M3).

*Pins: `repetition`.*

### C5 — Lookahead `&x`, `!x`

Evaluate `x` at `p` and **discard its entire effect** (position, value,
captures — engines checkpoint/roll back the capture store). Then:

```
&x  succeeds with ε at p  iff x succeeds
!x  succeeds with ε at p  iff x fails
```

A predicate is zero-width. It observes the **raw** next bytes: injected trivia
never applies inside a lookahead (S6), and a lookahead's body failures are not
part of the enclosing failure's expected set beyond the predicate itself.

*Pins: `lookahead` (negative), `rejects`, `lookbehind` (negative inside a scan
body). Positive lookahead is gap G1.*

### C6 — Behind guards `&<x`, `!<x`

At position `p`, evaluate whether `x` matches the text **ending at `p`**,
consuming nothing:

- `&<x` succeeds iff there exists `q ≤ p` with `(x, w, q) ⇓ (p, v)`;
- `!<x` succeeds iff no such `q` exists.

Bodies are restricted at compile time (X5): a case-sensitive literal is a
fixed byte window `w[p-|x|, p) = x`; a character class or case-insensitive
literal is the end-anchored flanking match. Anything else is a compile error.
The guard is capture-neutral (M3/C5).

*Pins: `lookbehind` (`!< %x61-7A` before `"*"`).*

### C7 — Rule references and recursion

A reference to rule `R` matches as `R`'s body does at the same position, with
the same value. Reference results are transparent for captures (V4) and
flattening: a reference does not add a tree level. Recursion is permitted when
it consumes input before recurring; left recursion is rewritten at compile
time (L1–L3) or rejected (X1). Memoization, program compilation, and caching
are unobservable optimizations (E1).

*Pins: `nesting`, `skip_trivia`, `lookahead`, `leftrec_arith`.*

### C8 — Atomic rules
`atomic R` builds `R` without trivia injection: it matches contiguously, sees
raw input, and — if it is an entry — receives no leading/trailing skip wrapper.
Apart from trivia interaction, atomic rules follow C1–C7 exactly.

*Pins: `atomic_skip` (the same sequence under a skip declaration, atomic and
non-atomic: the non-atomic body interleaves trivia and takes the S5 wrappers,
the atomic one rejects all four).*

### C9 — Direct left recursion (compile-time rewrite)

A rule whose ordered-choice branches include alternatives that begin with a
bare self-reference is **directly left-recursive**. The compiler rewrites it
at compile time into a chain of ordinary left-folding tier rules — the ANTLR 4
model — so the artifact contains plain atoms and every engine inherits the
semantics unchanged:

- Branches in source order are precedence tiers: **earlier alternatives bind
  tighter**. The non-recursive alternatives are the primary and act as the
  loosest operand.
- Tier `i` (for the `i`-th left-recursive branch, `suffix_i` being the branch
  without its leading self-reference, with every remaining self-reference
  rewritten to the previous tier) is:
  `T_i = T_{i-1} ( suffix_i )*`, with `T_0` = primary and the rule itself
  equal to the last tier. The fold is left-associative by construction.
- **L2 — branch restrictions.** A left-recursive alternative must begin with
  a *bare* self-reference (captures or predicates around it are rejected);
  its suffix must consume input (nullable suffixes are rejected); a rule with
  no non-recursive alternative, or consisting only of the self-reference, is
  rejected.
- **L3 — fold value.** The rule's value is exactly the flattened value of the
  rewritten loop grammar under V1/V3: a captured left-recursive rule flattens
  to `[primary_step, step₁, step₂, …]` in fold order (arrays hoist per V1);
  per-fold-step capture maps are not synthesized.
- **Indirect** left recursion (a cycle through other rules, including through
  the primary) is a compile error (X1).

*Pins: `leftrec_arith` (tiered precedence, left associativity, fold shape).*

---

## 5. Captures

### K1 — `x as name`

On success `(x, w, p) ⇓ (p′, v)`, yield `(p′, {name: flatten_named(v)})`.
On failure, no capture exists. Captures may repeat (e.g. inside a repetition);
consumers see them in source order (B1). Duplicate names inside one map merge
by V1 (right-biased).

*Pins: all `example` expectations; `atoms_lexical`, `nesting`, `repetition`,
`short_rep`.*

### K2 — Capture value

The captured value is the flattened value of the captured expression, with the
*named* flattening variant (V2/V3): an absent optional inside a capture is
`ε`, not `""`; an empty captured repetition is `[]`, not `""`.

*Pins: `repetition` (`dash` omitted on `"ab"`); gaps G5/G6.*

### K3 — Captures across sequence and choice

Captures thread through sequences in source order. Ordered choice exposes only
the winning arm's captures (M3). Uncaptured text is transparent to bindings:
bindings read named captures only (B1).

*Pins: `nesting`, `skip_trivia`.*

### K5 — Captured trivia (`skip = trivia capture: comments`)

When the skip declaration names a capture kind, matched trivia rides with the
**next successful capture** as an additional `comments:` entry; trailing trivia
attaches to the enclosing entry capture. Whitespace-only units are never
recorded. Captured trivia bytes never join span captures. Without the
`capture:` option, injected trivia is capture-free (S3).

*Pins: `trivia_capture` (acceptance); the attached `comments:` data is pinned
by the Ruby differential spec.*

---

## 6. Trivia injection (`skip = rule`)

### S1 — Injection points

A grammar may declare `skip = R`. At compile time an optional match of `R` is
inserted at token boundaries; this is a source-to-source rewrite, baked into
the artifact's atom graph (consumers need no special support):

- at the start of every sequence element (including rule references), except
  before a lookahead or an already-injected skip;
- before a bare terminal that forms a whole rule body;
- recursively inside alternatives, optionals, and named captures;
- inside a repetition body only before rule-reference children of a sequence
  body — scan bodies such as `( !"x" ANY )*` stay verbatim, and a single
  reference body relies on the reference's own leading injection;
- not inside lookaheads (S6);
- not in the skip rule itself or the rules it transitively references;
- not in atomic rules (C8).

*Pins: `skip_trivia` (interleaved trivia), gap G8 for the exemptions.*

### S2 — Skip rule constraints

The declaration must be a rule reference or an alternation of rule references,
and the rule must be **non-nullable**: a skip that can match empty would loop
at injection points. Both are compile errors.

*Pins: `skip_trivia` validity is compile-checked; the error paths are pinned by
compiler specs.*

### S3 — Capture-free, value-free

Injected trivia consumes input but contributes `ε` to the enclosing value and
no captures; its bytes never join span-joined captures.

*Pins: `skip_trivia` (examples contain `key`/`value` only).*

### S4 — Diagnostics suppression

Failures inside injected trivia never surface: deepest-failure positions and
expected sets point at real content. A skip that partially matched and then
failed is simply "no trivia here".

*Pins: `skip_trivia` rejection at `"abc = "`; the offset is asserted in the
recovery specs.*

### S5 — Entry boundaries

Non-atomic entry roots take leading and trailing trivia before the
full-consumption check (M0), so leading whitespace and trailing comments parse.

*Pins: `skip_trivia` (`"  abc = 42"`); trailing trivia is gap G10.*

### S6 — Lookahead exemption

A lookahead's body is never injection-rewritten: its contract is the raw text
ahead. Interiors stay exempt even through rule references.

*Pins: gap G8.*

---

## 7. Failure and diagnostics

### F1 — Deepest real-content failure

A failure carries the maximum position reached by a failed terminal on
real content. Engines MUST report the same offset for the same grammar and
input (this is the value exposed as `error.offset` by recovery, E2). The
rendered message, expected-set wording, line/column formatting, and cause-tree
shape are informative, not normative.

*Pins: recovery specs (offset equality across engines); corpus accept/reject
cases pin only success/failure.*

---

## 8. Bindings layer

Bindings run on the **flattened** tree after a successful parse. They never
change whether input parses.

### B1 — Capture collection

Walk the flattened tree: every map key contributes a value to the ordered list
for that name (breadth-first, source order); arrays are traversed. Bindings read
only named captures (no positional access to unnamed text).

### B2 — Scalar bindings

`capture -> field (type)` assigns the **first** collected value for `capture`
to `field`. If the capture is absent, the field is absent (not `nil`).

### B3 — Casts

Applied after preprocessing (B5), in this order:

| Type | Rule |
|---|---|
| `integer` | `Integer(value)` — invalid input raises a binding error |
| `float` | `Float(value)` — invalid input raises |
| `string` | scalar values only (text, number, boolean, nil); stringified; non-scalars raise |
| `boolean` | `true`, or case-insensitive `"true"`; everything else false |
| other/unknown | passed through unchanged (e.g. enum keys) |

*Pins: `bindings_types` (integer); float/boolean are gap G7.*

### B4 — Array bindings

A path containing `[]` groups capture names into one array of objects:
`capture -> items[].field (type)`. The list length is the maximum capture count
in the group; element `i` takes the `i`-th value of each capture, omitting
fields whose capture has no `i`-th value. At most one `[]` level is supported;
any other dot/array nesting is rejected at apply time.

*Pins: gap G6.*

### B5 — Preprocessing

`preprocess: step` names a declared step list, applied before the cast.
`table_lookup T from -> to` maps the value through table `T`'s `from` column to
its `to` value; a value with no row passes through unchanged. Steps apply in
declaration order. Unknown ops/steps are errors.

*Pins: `preprocess_table` (accept/reject; binding-level example is gated on a
native table-on-bind limitation noted in the case).*

### B6 — Canonical equality (tests)

`capture` and `example` expectations compare through one canonical form:
maps stringify keys and recurse, arrays recurse, `nil`/booleans/integers are
themselves, floats render as their **JSON number text** (shortest round-trip
digits in the JSON gem's notation — the B6 canonical float form used for
checksums), and everything else is `String(value)`. This removes
engine/representation differences; a test can never pass on one engine and
fail on another over representation. Float expectations ride the artifact
checksum, so the canonical float form is load-bearing across engines
(`bindings_float`).

---

## 9. Data-driven alternatives and tables

### D1 — `alt from_table "T" column "C"`

Expands at **compile time** into an ordered choice of exact literals, one per
non-empty distinct value of column `C`, sorted **longest first** (then
lexicographically). Longest-first is normative: with overlapping values
(`"A"`, `"AB"`) it is what makes `"AB"` reachable under ordered choice (C2).

*Pins: `preprocess_table` (non-overlapping values); overlap is gap G9.*

### D2 — Table manifest

Referenced tables are embedded as rows in the artifact and covered by its
checksum; consumers resolve `table_lookup` from the artifact, never from the
filesystem. Hash-shaped tables acquire a `name` column from their key; array
tables are rows as-is with string keys.

*Pins: `preprocess_table` + `stages.yaml`.*

### I1 — `use name` (compile-time composition)

`use name` at the top of a source file loads `name.parg` from the configured
import directories and merges it **at compile time**:

- every imported rule is renamed `name.rule`, and references inside imported
  rules are rewritten to match; capture names are preserved;
- imported entries, bindings, preprocess steps, tests, and docs merge with the
  same prefix (`name.entry`);
- imports are recursive; cycles and missing files are compile errors;
- the artifact bakes the expansion — consumers never resolve imports, and an
  imported grammar's behavior is exactly the merged grammar's behavior under
  C1–C7.

A `.parg` with no compiled sibling artifact is an **import helper**: its only
contract is what importing grammars observe.

*Pins: `helper`, `imports`.*

---

## 10. Test phases in the artifact

### A1 — `accept` / `reject`

`accept "w"`: `parse(entry, w)` succeeds under M0. `reject "w"`: it fails.
These pin the parse relation only.

*Pins: every corpus case.*

### A2 — `capture "w" { k: v }`

Compares the **grammar-layer** capture tree canonically (B6): raw named
captures, no bindings applied, no preprocess. A grammar can pin parse behavior
before any bindings exist. Values are the captured flattened values (text for
text captures).

*Pins: `atoms_lexical`, `casefold`, `entries`, `imports`, `lookbehind`,
`nesting`, `repetition`, `short_rep`, `skip_trivia`, `trivia_capture`.*

### A3 — `example "w" { k: v }`

Compares the **bindings-layer** result: bound, preprocessed attributes, exactly
what `parse_and_bind` hands the consumer. Requires a `bindings` section to exist
for the entry; without one, compilation fails with an authoring error.

*Pins: `bindings_types` (scalar casts), `bindings_array` (array paths),
`bindings_casts` (boolean).*

### A4 — `shape "w" <value>`

Compares the **whole flattened parse tree** canonically (B6) against an
arbitrary expectation value (text, number, boolean, null, array, or nested
object). This is the only phase that can observe V1 merge laws and V3
repetition flattening, because `capture` asserts per-name first values only.
No bindings section is required.

*Pins: `repeat_flatten` (V3), `merge_laws` and `merge_array` (V1).*

The compiler runs all in-file tests at build time: a failing test fails the
build. The artifact carries the tests so every engine replays the same
expectations.

---

## 11. Static obligations (compile time)

These are part of the language: a compiler MUST reject the grammar, not defer
to runtime.

### X1 — Left recursion (indirect)

Direct left recursion is rewritten at compile time (C9). **Indirect** left
recursion — a cycle that reaches the rule through other rules, including
through the rewritten rule's primary — is a compile error. Unguarded left
recursion loops in a PEG.

### X2 — Branch shadowing

Within an ordered choice:

- a branch that can match empty before the last branch is an error (it shadows
  all later branches);
- two identical literal branches are an error;
- a shorter literal branch placed before a longer literal branch it prefixes is
  an error ("reorder longest-first").

### X3 — Ordering warnings

Branches with shared first bytes, or whose first set is not statically known,
emit a warning that the choice is order-dependent. Warnings are recorded in the
artifact lint section; they do not fail compilation.

### X4 — Lexical/representation rejections

- An empty string literal is rejected except as the zero-width marker (T6).
- `[ … ]` is the optional form. A bracket containing a sequence of two or more
  character classes is rejected (it would parse as an optional sequence of
  single characters and can match empty; the multi-range class is the
  alternation spelling).
- Empty literals cannot be used to force zero-width matches outside captures.

### X5 — Behind-guard bodies

The body of `&<` / `!<` must be a case-sensitive literal, a case-insensitive
literal, a character class, or a builtin class reference; anything else is a
compile error (an arbitrary rule has no bounded behind-window).

### X6 — Skip validity

See S2: rule-reference shape and non-nullability are compile errors.

---

## 12. Engines and artifacts

### E1 — Engine decline is unobservable

Engines may decline to execute any sublanguage: the Ruby VM marks a grammar
`:fallback` on unsupported shapes or step-budget exhaustion; the native engine
aborts to the interpreter on `CustomRef` (dynamic artifacts). Decline MUST NOT
change the result. Whatever engine runs, the flattened tree, the capture lists,
and accept/reject MUST be identical (structural comparison; text may be string
or slice).

*Pins: `trivia_capture` (Ruby bytecode VM declines to the interpreter on its
skip/trivia shapes and still produces the corpus result); not directly
corpus-expressible for the native interpreter abort, which the differential
gate covers.*

### E2 — Recovery extension (R1)

`parse_recovering(entry, w)` never raises:

- success → `{ok: true, shape: <tree>}` (identical to `parse`);
- failure → `{ok: false, captures: {name: [values…]}, error: {offset, …},
  consumed_upto: n}`.

`error.offset` is the F1 deepest real-content position. `consumed_upto` is the
maximum input position reached. `captures` is a **journal superset**: it
includes captures observed on branches that later failed, and therefore MUST
NOT be used to infer M3 transactional behavior. The strict contract remains
`parse`. Implementations may satisfy recovery with a journaling re-parse; the
journal's exact rollback point is not normative, but the offset and
`consumed_upto` are.

*Pins: recovery specs in parsanol-ruby/parsanol-rs/parsanol-ts.*

### E3 — Artifact envelope and compile parity

An artifact is `parsanol-tree/v2`: `entries` (root, portable grammar, bindings),
`bindings`, `preprocess`, `tables`, `tests`, `skip`, optional `customs`/
`states`/`dynamic`, `source`, `source_hash` = SHA-256 of the source text,
`compiler_version`, and `checksum` over the envelope. `source_hash` binds the
artifact to the exact `.parg` text (comments included).

Compile parity compares envelopes produced from the same source **excluding
`compiler_version` and `checksum`** (those legitimately vary by compiler
build). Everything else, including `source_hash`, is normative. Engines MUST
parse the embedded portable grammar, never re-derive it from `source` (the
source is carried for dynamic/native-abort fallback, not as the runtime
contract).

---

## 13. Corpus coverage matrix

Every current corpus case, the rules it pins, and the sharp edges it covers.
Gaps in the other direction (rules without cases) are in §14.

| Corpus case | Rules pinned | Sharp edge covered |
|---|---|---|
| `atoms_lexical` | T1, T3, C1, C7, K1, V1, V2, A1, A2, M0 | byte-range classes; text captures; capture-phase assertions |
| `bindings_types` | C3 (exact 2*2), K1, K2, B1, B2, B3 (integer), A1, A3, M0 | integer cast; the bindings-layer test phase |
| `casefold` | T2, T1, C1, C3, K1, A1, A2, M0 | case-insensitive literal: accept/reject/reject-prefix |
| `entries` | C7, T3, C3, K1, A1, A2, M0 | several entries over one rule set; entry-scoped tests |
| `helper` | I1 | import helper: a source-only grammar |
| `imports` | I1, T1, C1, C7, K1, B1, A1, A2, M0 | `use` merge, qualified reference `helper.code` |
| `lookahead` | T1, C1, C5 (negative), C7, M0, A1 | zero-width predicate after a repetition |
| `lookbehind` | T3, C5 (negative), C6 (both signs), K1, V3, M0, A1, A2 | behind-guard on a class; scan body `( !"*" ANY )` verbatim under C2 |
| `nesting` | T3, C1, C2, C3, C7, K1, V4, M0, A1, A2 | nested references; rejected `"a..b"` |
| `preprocess_table` | D1, D2, B5, B3 (string), M0, A1 | compile-time table expansion; binding preprocess |
| `rejects` | T3, T5, C1, C3 (0*), C5 (negative), M0, A1 | unclosed quote; empty string accepted |
| `repetition` | T1, C3 (exact), C4, K1, V2, V3, B1, B3 (string), A1, A2, M0 | optional absent capture omitted; `"abc"` rejected by M0 |
| `short_rep` | T3, C3 (bounded), K1, V3, B3 (string), A1, A2, M0 | upper bound then M0 rejection |
| `skip_trivia` | S1, S2, S3, S4, S5, T1, T3, C1, C7, K1, B1, A1, A2, M0 | interleaved trivia; entry-leading skip; failure after skip |
| `trivia_capture` | K5, S1, S2, S3, S4, S5, T1, T3, C3, C5, C7, K1, A1, A2, M0, E1 | comment trivia, nested block comments, VM decline path |
| `lookahead_positive` | C5 (positive), T1, C3, M0, A1 | positive lookahead, zero width |
| `zero_width_marker` | T6, T3, C3, K1, A1, A2, M0 | `"" as name` presence marker |
| `byte_sequence` | T4, T3, C3, M0, A1 | CRLF byte sequence; lone CR/LF rejected |
| `skip_lookahead` | C5, S1, S4, S5, S6, T1, M0, A1 | lookahead sees raw text; entry trailing trivia |
| `trailing_trivia` | S1, S5, T1, C3, M0, A1 | trailing whitespace before full consumption |
| `table_overlap` | D1, D2, C2, T1, M0, A1 | longest-first table expansion |
| `casefold_nonascii` | T2, T1, C1, M0, A1 | Unicode case folding |
| `optional_capture` | C4, K1, K2, V2, M0, A1, A2 | absent optional captured as nil |
| `bindings_array` | B1, B2, B3, B4, C3, K1, A1, A3, M0 | array-of-objects bindings |
| `bindings_casts` | B2, B3, K1, C1, A1, A3, M0 | boolean cast |
| `repeat_flatten` | V3, C3, K1, A1, A2, A4, M0 | hash-only retention; text concatenation |
| `merge_laws` | V1, C1, K1, A1, A4, M0 | right-biased duplicate keys; text dropped beside maps |
| `merge_array` | V1, V3, C1, C3, K1, A1, A4, M0 | array hoisting in sequence merge |
| `leftrec_arith` | C9, C2, C3, C7, K1, A1, A4, M0 | tiered precedence, left associativity, fold shape |
| `atomic_skip` | C8, S1, S5 | atomic body is contiguous and wrapper-free; the non-atomic twin interleaves trivia |
| `stages.yaml`/`overlap.yaml` | D2 | table rows embedded in the artifact |
| all in-file tests | A1, A2, A3, A4, B6 | canonical equality across engines |

## 14. Coverage gaps

Rules without a corpus case are tracked in **parsanol-rs#254**. Summary:

| # | Rule | Missing case |
|---|---|---|
| — | — | none: G7f (float canonical form, rs#267) and G8b (atomic-vs-skip, `atomic_skip`) are closed; the remaining pins are the not-corpus-expressible X/E classes |

Not corpus-expressible (pinned by compiler/runtime specs): X1–X6 and E2.
E1 is pinned indirectly — `trivia_capture` forces the Ruby VM's decline path.

---

## 15. Changing this document

1. A normative change is a language change: it requires a corpus case (or a
   spec for X/E rules) in the **same PR series**, updated rule text, and a
   matrix update. WPT rule 3 applies — the red case is the issue tracker.
2. A corpus PR that adds or changes a case must cite the rule ID(s) it pins in
   the case's `## Semantics:` line (see the corpus README).
3. When this document and the guide diverge, this document wins; fix the guide
   in the same PR.
