# PARG — the parsanol grammar language

*Programming guide and language reference. Version: 0.1 (this document
describes what ships in parsanol-ruby `Parsanol::PARG` today).*

PARG is a text language for writing parsanol grammars. One `.parg` file is the
**single source of truth** for a grammar: it compiles to a checksummed
**artifact** whose grammar section is the same portable JSON the native
engines (Ruby ext, FFI, wasm, Rust) register. Humans review the text;
machines consume the JSON; the checksum binds them together.

```
grammar.flavor.parg  ──compile──▶  artifact.json (portable grammar + bindings
     ▲                              + preprocess + tables + sha256)
     │                                      │
     └── the committed contract             ├── parsanol-ruby (atoms, parse)
                                            ├── parsanol-rs    (Grammar::from_json)
                                            └── @parsanol/wasm
```

The design has one rule: **a grammar or binding change is one edit in one
file**, and every language runtime inherits it — proven by the artifact
checksum and the conformance corpus.

## Quick start

```
# demo.parg
grammar Demo version "1.0.0" {
  digit = %x30-39
  number = 1*digit
  space = " "
  publisher = %i"iso" / %i"ieee"

  iso_identifier = publisher as publisher space number as number
}

bindings iso_identifier {
  publisher -> publisher (string)
  number -> number (integer)
}

entry identifier: iso_identifier
```

```ruby
require "parsanol"

document = Parsanol::PARG::Parser.new(File.read("demo.parg")).parse
result   = Parsanol::PARG::Compiler.compile(document, tables_dir: "tables")
File.write("demo.artifact.json", JSON.generate(result.envelope))

artifact = Parsanol::PARG::Artifact.load("demo.artifact.json")
artifact.parse("identifier", "iso 12345")        # parsanol-shape tree
artifact.parse_and_bind("identifier", "iso 12345")
# => { publisher: "iso", number: 12345 }
```

`parse` is **native-first**: the envelope's grammar section is the exact
portable JSON the Rust engine registers, so the default path is a straight
register-and-run through `parsanol-rs` — no Ruby recompilation. The Ruby
atom runtime remains available explicitly (`mode: :ruby`) and serves as
the fallback on platforms without the native extension. The two paths are
held to parity by spec.

`Parsanol::PARG::Import.import(:abnf, text)` (also `:ebnf`, `:pest`) returns
PARG source generated from a foreign grammar — commit the result and compile
it like hand-written PARG.

## Syntax reference

### Lexical

- `#` starts a comment, running to end of line.
- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`. Rule names are case-sensitive.
- **One rule per line.** Newlines are significant: a rule body ends at the
  newline. Sections (`grammar`, `entry`, `bindings`, `preprocess`) are
  line-oriented throughout.
- Keywords: `grammar version as alt from_table column bindings preprocess
  entry table_lookup`. They cannot name or reference rules.

### Terminals

| Form | Meaning |
|---|---|
| `"abc"` | exact literal (case-sensitive) |
| `%i"abc"` | case-insensitive literal |
| `%s"abc"` | exact literal (spelling for imports; same as `"..."`) |
| `%x41` | one byte 0x41 |
| `%x41-5A` | one byte in the range 0x41–0x5A |
| `%x0D.0A` | a sequence of bytes: 0x0D then 0x0A |

String escapes: `\"`, `\\`, `\n`, `\t`, `\r`.

### Operators

| Form | Meaning | Compiles to |
|---|---|---|
| juxtaposition | sequence | `Sequence` |
| `a / b` | **ordered** choice (first match wins) | `Alternative` |
| `[ x ]` | optional (maybe) | `Repetition(0,1,:maybe)` |
| `( x )` | grouping | — |
| `*x` | zero or more | `Repetition(0, ∞)` |
| `1*x` | one or more | `Repetition(1, ∞)` |
| `2*4x` | two to four | `Repetition(2, 4)` |
| `4x` | exactly four | `Repetition(4, 4)` |
| `!x` | negative lookahead | `Lookahead(false)` |
| `&x` | positive lookahead | `Lookahead(true)` |
| `!<x` | negative behind-guard | `Lookbehind(negative)` |
| `&<x` | positive behind-guard | `Lookbehind(positive)` |
| `x as name` | capture — names the parse result | `Named(name)` |

Repetition prefixes bind one primary: `3*(a b)` — parenthesize composites.
A capture binds the primary it follows: `dash number as part` captures
`number` only — and after a repetition's closing paren, `*( x ) as name`
captures the whole repeated run (an `as` inside the body's own parens,
`*( ( x ) as each )`, names each iteration's `x`).

### Rule bodies: the brace form (self-delimiting rules)

A rule body is normally **newline-terminated** — one line, one rule. The
**brace form** makes the body self-delimiting:

```
## Publisher code: case-insensitive tag; raw input is captured.
publisher = {
  %i"iso" / %i"ieee"
}

## ISO-style identifier: publisher, one space, a number.
iso_identifier = { publisher as publisher space number as number }
```

Inside braces, newlines and comments are whitespace and the body extends
to the matching `}`. Normative rules:

1. A brace body may open only at the **rule head** (immediately after
   `=`). Brace groups are not expressions inside a body — composites
   group with `( ... )` — so `{` stays unambiguous everywhere.
2. The body ends at the first unmatched `}`. After it, the next
   declaration begins; no continuation syntax exists.
3. `##` doc comments attach to the following rule in either form; with
   braces the attachment is structural (one block, one comment) rather
   than line-positional.
4. Both forms compile to the same atom stream — engines never see the
   difference.

**Compatibility:** `{` after `=` is new syntax. Verified 2026-10-24 over
all 67 PARG sources in the ecosystem (conformance corpus, benchmarks,
pubid-grammar): zero rule bodies contain `{` — the only brace at that
level is the `preprocess` section header. The form is additive, needs no
version bump, and changes no existing artifact byte.

Style: prefer the brace form for anything that wraps, the line form for
short bodies; `parg lint --style` flags a grammar that mixes them
heavily.

*Specified 2026-10-24; implementation tracked in parsanol-ruby (brace
rule bodies), including the self-host gate and the pubid-grammar
`parg.json` update.*

### Core rules (RFC 5234 prelude)

The RFC 5234 core rules are predeclared in every grammar — no
`digit = %x30-39` boilerplate:

| Rule | Definition |
|---|---|
| `ALPHA` | `%x41-5A / %x61-7A` |
| `BIT` | `"0" / "1"` |
| `CHAR` | `%x01-7F` |
| `CR` | `%x0D` |
| `CRLF` | `%x0D.0A` |
| `CTL` | `%x00-1F / %x7F` |
| `DIGIT` | `%x30-39` |
| `DQUOTE` | `%x22` |
| `HEXDIG` | `DIGIT / "A" / "B" / "C" / "D" / "E" / "F"` |
| `HTAB` | `%x09` |
| `LF` | `%x0A` |
| `LWSP` | `*( WSP / CRLF WSP )` |
| `OCTET` | `%x00-FF` |
| `SP` | `%x20` |
| `VCHAR` | `%x21-7E` |
| `WSP` | `SP / HTAB` |

A grammar's own rule of the same name **shadows** the prelude — existing
grammars that define `digit` (any case) keep working unchanged.
`parg lint` reports core-rule shadows (`core-rule-shadow`) and suggests
dropping the local definition; the ABNF importer stops emitting core
rules once the prelude ships.

*Specified 2026-10-24; shadowing keeps every published grammar
byte-identical — implementation tracked in parsanol-ruby (core rules).*

### Unicode position

Parsanol is **Unicode-native by destination, byte-exact by contract**:

- The wire (PARSANOL-SHAPE-v2) fixes **byte offsets and byte lengths**;
  rendered columns are character counts. Every engine agrees byte-for-byte.
- String literals already match UTF-8 byte sequences exactly — multibyte
  literals, CJK, emoji work today.
- On the roadmap, in tiers, each gated by a unicode corpus (CJK, emoji
  ZWJ sequences, combining marks, RTL, astral plane) replayed
  byte-identically across Ruby, Rust, wasm and TypeScript:
  - **U1 — correctness floor**: `.` and negated classes advance by
    codepoint (never split one); columns become character-based.
  - **U2 — folding**: `%i` uses Unicode simple case folding, the same
    table in every engine.
  - **U3 — classes**: `\w`, `\d` and general categories from shared
    tables, feature-gated on wasm for payload size.

*Tracked in parsanol-rs (unicode-native engines).*

### Behind-guards

`!<x` / `&<x` inspect the text **behind** the current position and
consume nothing — the flank guards for intraword constraints
(constrained emphasis must not fire mid-word):

```
emph = ( !< ALPHA "*" 1*( !star ANY ) "*" ) as emph
```

- a **character-class body** (or builtin class reference) compiles to
  the end-anchored flanking regex — the class must (not) match the
  text ending at the position
- a **case-sensitive literal** compiles to the fixed byte window;
  case-insensitive literals compile to an `(?i:…)` regex
- anything else (rule references included) is a compile error — a
  behind-window over an arbitrary rule has no bounded expression

### Character classes

A character class is a hex range — `%x5f` (one code point),
`%x21-2f` (a range) — or an **alternation of ranges**:
`(%x21-2f / %x3a-40 / %x5b-60 / %x7b-7e)` is the punctuation set.
`[ … ]` is NOT a class: it is the **optional** form. Brackets whose
elements are all classes fail compilation with the alternation
spelling in the message (an optional sequence of single-character
classes can match empty, and captures over it yield nil).

### Data-driven alternatives

```
stage_abbr = alt from_table "stages" column "abbr"
```

Expands at compile time into literal alternatives built from the named
table (see [Tables](#tables)), **sorted longest-first**. This is the
declarative replacement for computed rules: the same Tier-2 data serves the
grammar, the model's enum payloads, and preprocessing.

### Sections

`grammar NAME version "X.Y.Z" { rules }` — the rules. One grammar block.

`entry NAME: rule` — declares an artifact entry point. Multiple entries
share the rule set.

```
bindings iso_identifier {
  publisher -> publisher (string)
  year -> year (integer, 0..1)
  stage -> stage (string) preprocess: stage_code
  supplement_no -> supplements[].number (integer, 0..*)
}
```

A binding is `capture -> field (type [, cardinality]) [preprocess: step]`.
Types: `string`, `integer`, `float`, `boolean` (unknown types pass through —
e.g. enum keys). Cardinalities: `1`, `0..1`, `1..*`, `0..*`. `[]` paths
(grouping captures into arrays of objects) support **one** level; deeper
nesting is binder code.

```
preprocess stage_code {
  table_lookup stages abbr -> code
}
```

Steps are declarative data operations. v1 ships `table_lookup` (map the
value through a table column pair). Anything not expressible here is
application logic and belongs above the binding layer.

### In-file tests

A `test` section pins a grammar's observable behavior. The compiler runs
it at build time (a failing test fails the build) and the artifact
carries it, so every engine re-plays the same expectations.

```
test main {
  accept "AB2020"
  reject "AB20"
  capture "AB2020" { pub: "AB" }
  example "AB2020" { pub: "AB" }
}
```

Three assertion phases:

- `capture` — the **grammar layer**: expectations match the raw capture
  tree (`capture -> value` pairs). No `bindings` section needed — a
  grammar can pin its parse behavior before any attribute mapping
  exists.
- `example` — the **bindings layer**: expectations match the bound,
  preprocessed attribute hash, i.e. exactly what `parse` hands the
  consumer. Requires a `bindings` section; without one the compiler
  rejects the test with an authoring error instead of failing obscurely.
- `shape` — the **whole-tree layer**: the expectation is the canonical
  flattened parse tree itself (text, array, or object). This is the only
  phase that can observe repetition flattening and sequence merge laws,
  so structural contracts use it:

  ```
  test main {
    shape "aab" [ { x: "a" }, { x: "a" }, { y: "b" } ]
  }
  ```

Expectations compare through one canonical form (terminals reduce to
their text, structure recurses), so a test never passes on one engine
and fails on another over representation differences. `accept` /
`reject` need no explanation — the input must parse / must not parse.
Expectation values may be strings, numbers, `true`/`false`, `null`,
arrays, and nested objects.

Tests in a multi-entry grammar name their entry (`test main { ... }`);
a single-entry grammar may omit it.

### Tables

`alt from_table` and `table_lookup` resolve `NAME.yaml` / `NAME.yml` /
`NAME.json` under the compile-time `tables_dir` (artifact consumers resolve
against the artifact's directory). A hash table becomes rows keyed by
`name`; an array table is rows as-is. Tables referenced by the grammar are
recorded in the artifact's `tables` manifest and shipped with it.

## Semantics

PARG has **PEG semantics**: ordered choice, greedy repetition, no ambiguity.
There is no global ambiguity to report because first match wins — which is
exactly why the compile-time lint below exists.

The normative small-step rules — the match relation, capture and flattening
laws, trivia rewrite, bindings obligations, diagnostics, and the corpus
coverage matrix — live in [parg-semantics.md](parg-semantics.md). This guide is
the friendly edition; the semantics document wins where they disagree.

**Direct left recursion is rewritten at compile time** (the ANTLR 4 model):
`expr = expr "*" expr / expr "+" expr / INT` becomes a chain of left-folding
tier rules, with alternatives in source order binding tightest-first and the
non-recursive alternatives as the primary. The artifact carries ordinary
atoms, so every engine runs the fold identically; the fold value is the
flattening of the equivalent loop grammar. Branch restrictions (bare leading
reference, consuming suffix) and **indirect left recursion** (still rejected)
are compile errors — see the normative rules (C9, X1) in
[parg-semantics.md](parg-semantics.md).

### Recovery (best-effort partial parses)

`Artifact#parse_recovering(entry, input)` never raises: on success it
returns `{"ok": true, "shape": <tree>}`, and on failure it returns

```ruby
{ "ok" => false,
  "error"    => { "offset" => 12, "message" => "..." },
  "captures" => { "atom" => [{atom: "A"@0}], ... } }
```

- `error.offset` is the deepest failure position (same value the cause
  tree reports).
- `captures` carries every capture **observed before the failure** —
  including captures from branches that later failed (a documented
  best-effort superset, identical to the rs recovery journal). Values
  are the wrapped capture hashes; Slices stringify to their content.
- The observed captures come from a journaling re-parse on the Ruby
  engine (tree parity with the native engine is enforced by the
  differential specs). Success paths never journal.

Use recovery for editors, linters, and any consumer that needs the
"what did match" answer alongside "where did it stop matching". The
raise-on-failure `parse` remains the strict contract.

### Repetition flattening (parslet parity)

Capture flattening follows parslet exactly, including its repetition
rules — verified byte-for-byte against parslet 2.0.0:

- a repetition **all of whose iterations are text** concatenates into
  one string
- a repetition **any of whose iterations is a capture hash** keeps
  **only the hash iterations** and silently drops the rest —
  parslet's `CanFlatten#flatten_repetition` behavior, reproduced in
  parsanol-ruby#231
- an uncaptured sequence rule inside such a repetition contributes its
  child captures as one array-of-hashes iteration — which the rule
  above then drops if any other iteration is a hash

The stable idiom is to **capture every structural rule** (`g = ( go
1*( gu ) gc ) as grp`) so each iteration yields one hash, and unwrap
in the consumer — or keep repetition bodies homogeneous.

## Skip rule (trivia injection)

One declaration per grammar turns implicit trivia — whitespace, comments —
into engine-consumed trivia instead of hand-placed `[ ws ]` terms in every
rule:

```
grammar Lml version "2.0.0" {
  skip = trivia
  trivia = 1*( ( 1*" " ) / comment )
  comment = "(*" *( comment / ( !"*)" ANY ) ) "*)"
  ...
}
```

Semantics:

- An **optional match of the skip rule is injected before every terminal**
  of every rule (memoized, injected by reference). Entry points also take
  leading and trailing skips, so tail comments parse.
- The skip rule must be **non-nullable** (a nullable skip loops at
  injection points) and may only reference rules (a rule reference or an
  alternation of references). The referenced rules — and everything they
  reference — build without injection, so recursive trivia rules
  (nested block comments) work.
- Trivia is **capture-free**: injected skips are ignored atoms, so their
  bytes never appear in captures or join capture spans.
- **Diagnostics stay out of trivia**: failures inside injected trivia
  never surface — deepest-failure positions point at real content, and
  rendered cause trees and failure messages omit the skip machinery.
- Artifacts without `skip` are byte-identical to grammars compiled
  without the declaration; the envelope records `skip` as the trivia
  rule's source.

### Captured trivia (phase 2)

`skip = trivia capture: comments` attaches comment-shaped trivia to the
capture it precedes, under `comments:` — comments become programmatic
data without dedicated capture rules:

```
skip = trivia capture: comments
trivia = 1*( ( 1*" " ) / line_comment / block_comment )
```

- capturers are the rules the declaration (transitively) references
  whose leading literal is non-whitespace — the comment shapes
- matched trivia rides with the NEXT successful capture; trailing
  trivia attaches to the enclosing entry capture
- whitespace is never recorded (the DSL's `skip :rule, whitespace:
  :kind` records marker-less units verbatim under the declared kind —
  the source-preserving mode; units carry their input offsets)
- `comments:` appears only when trivia actually preceded a capture,
  so plain `skip` grammars stay byte-identical
- captured bytes never join span captures (the injection span
  discipline is unchanged)
- on the Ruby engine: capture grammars run on the interpreter (the
  bytecode VM declines them); native-engine parity ships with the
  trivia wire round

### Atomic rules

Injection is *before every terminal*, including inside a rule's own
repetition runs — so `word = 1*( ALPHA )` under a whitespace skip matches
`"a b"` as one word. Token-shaped rules opt out:

```
atomic word = ( 1*( ALPHA ) )
```

An atomic rule's body builds **without injection entirely** (no
inter-iteration trivia, no entry-boundary skips if the rule is an
entry): it matches its input contiguously. References *inside* an atomic
rule keep their own declarations' behavior. `atomic` is a reserved
keyword.

## The lint (order-dependence and shadowing)

ABNF and EBNF readers assume alternatives are interchangeable. Under PEG
semantics order is decisive, so the compiler runs a first-set analysis on
every alternative and reports:

- **ERROR — shadowed**: an earlier literal branch is a prefix of a later
  one (`"iso" / "iso/iec"`). Reorder longest-first. This is the classic
  silent-failure class of PEGs, made a build failure.
- **ERROR — empty shadowing**: a non-final branch can match empty input.
- **ERROR — duplicate** branches.
- **ERROR — left recursion** (above).
- **WARNING — order-dependent**: branches share first bytes. Recorded in
  the artifact (`lint.order_warnings`) so consumer CI can review them.

## The artifact

> **Runtime-state boundary.** Artifacts whose envelope carries
> `"dynamic": true` — grammars using the `state`/`set`/`switch` atoms or
> `custom` bindings — ride the **Ruby engine only**. parsanol-rs and
> @parsanol/wasm reject such artifacts loudly at the boundary (a
> `dynamic` envelope never silently mis-parses). Flavor owners targeting
> all three runtimes must keep those grammars Ruby-tier or split the
> stateful rules out.

```json
{
  "version": "1.2.0",
  "grammar": "Demo",
  "shape": "parsanol-tree/v2",
  "binding_version": 1,
  "entries": {
    "identifier": {
      "root": "iso_identifier",
      "grammar": { "atoms": ["…portable Grammar JSON…"], "root": 0 },
      "bindings": [ { "capture": "year", "path": "year",
                      "type": "integer", "card": "0..1",
                      "preprocess": null } ]
    }
  },
  "preprocess": { "stage_code": [ { "op": "table_lookup", "table": "stages",
                                    "from": "abbr", "to": "code" } ] },
  "tables": { "stages": "stages.yaml" },
  "lint": { "order_warnings": ["…"] },
  "source": "…the original .parg text…",
  "checksum": "sha256:…"
}
```

- `entries[].grammar` is the **portable Grammar JSON** — the exact format
  `parsanol-rs` (`Grammar::from_json`), the wasm surface, and the Ruby
  native extension register. One serialization, four engines.
- `source` embeds the PARG text: an artifact is self-contained, and a Ruby
  runtime can recompile atoms without the original file.
- `checksum` = sha256 over the canonicalized envelope (sorted keys,
  checksum excluded). `Artifact.load` verifies it and **fails loudly on
  mismatch** — never silently falls back.
- Semver: capture renames/removals → major; new alternatives → minor;
  literal fixes → patch. `version` and `binding_version` move separately:
  model-side-only changes bump `binding_version`.

## Importing foreign grammars

`Parsanol::PARG::Import.import(kind, text)` parses a foreign grammar and
returns equivalent **PARG source** (self-checked by re-parsing). Commit the
result; the `.parg` file stays the single source of truth. Each importer
documents its semantic conversions in the emitted header.

### ABNF — RFC 5234 + RFC 7405 (`:abnf`)

| ABNF | PARG |
|---|---|
| bare `"abc"` — **case-insensitive** | `%i"abc"` |
| `%s"abc"` (case-sensitive) | `"abc"` |
| `%x41-5A`, `%x0D.0A`, `%d13`, `%b1010` | `%x41-5A`, `%x0D %x0A`, `%x0d`, `%x0a` |
| `n*m`, `*x`, `3x`, `[x]`, `(...)`, `/` | same shapes |
| `rule =/ alt` (incremental) | merged into one alternative |
| rule names (case-insensitive, `-`) | lowercased, `-` → `_` |
| RFC 5234 core rules (ALPHA…) | emitted unless locally defined |
| `<prose-vals>` | **rejected** — not machine-parseable |

**The one deep semantic difference:** ABNF alternation is unordered; PARG's
is ordered. The compile-time lint flags every order-dependent branch the
import produces, so mechanical transliterations become reviewable instead
of silently different.

### EBNF — ISO 14977 (`:ebnf`)

| ISO EBNF | PARG |
|---|---|
| `"…"`, `'…'` terminals | exact strings |
| `,` sequence / `|` alternation | juxtaposition / `/` |
| `[x]` optional / `{x}` zero-or-more | `[ x ]` / `*( x )` |
| meta-identifiers (case-insensitive) | downcased |
| `term - exception` (syntactic exception) | `!( exception ) term` — exact when the exception matches a prefix of the term's match; each occurrence noted in the header |
| `? special sequences ?` | **rejected** |

### pest — Rust PEG (`:pest`)

| pest | PARG |
|---|---|
| `\|`, `!`, `&`, `*`, `+`, `?` | direct (postfix → PARG prefix/`[ ]`) |
| `"lit"` / `^"lit"` | `"lit"` / `%i"lit"` |
| `'a'..'z'` | `%x61-7a` |
| builtins (`ASCII_DIGIT`, `ASCII_ALPHA`, `ANY`, …) | `%x` ranges |
| `~` | sequence **plus a header note**: pest inserts implicit WHITESPACE there, PARG does not — whitespace must be explicit |
| `_{ }` / `@{ }` / `${ }` modifiers, `name_` silent rules | accepted, noted; captures stay enabled |
| `PUSH/POP/PEEK/EOI/SOI`, `WHITESPACE`/`Comment` rules | **rejected** with an explanatory error |

## lutaml-model integration

PARG artifacts are the **"serialization from string" path** of lutaml-model:
the grammar fills information models declared with lutaml-model's
attribute/mapping DSL. Registration goes through lutaml-model's own
`FormatRegistry` extension point:

```ruby
Parsanol::PARG::Lutaml.register(
  IsoIdentifier,
  format_name: :pubid_iso,
  artifact: "artifacts/iso.json",
  entry: "identifier",
)

IsoIdentifier.from_pubid_iso("ISO/CD 12345")
# => #<IsoIdentifier publisher: "ISO", stage: "draft20", number: 12345>
```

`register` wires the artifact's parse + bindings + preprocessing into the
model class and registers the format (with `error_types` ← parsanol parse
errors) in `Lutaml::Model::FormatRegistry`. Render (`to_<format>`) arrives
with artifact render specs.

## SOTA positioning (2023–2026 literature)

The recent research converges on exactly the primitives PARG ships:

- **Grammar-constrained generation** (XGrammar, arXiv:2411.15100, 2024;
  XGrammar-2, 2026; llguidance/"Practical Grammar-Based Constrained
  Decoding", 2024) — treats *compiled, serialized grammar artifacts* as the
  interchange unit and precomputes context-independent structure. PARG's
  checksummed artifact + portable grammar JSON is the same contract for
  parsers, and is the natural export target for constrained-decoding
  backends later.
- **PEG ordered choice as a hazard** ("PEGs Made Practical"; pegen's docs;
  community debates 2024) — silent shadowing is the recurring complaint.
  PARG's first-set lint turns the two detectable classes (prefix shadowing,
  empty-matchable non-final branches) into build failures and records the
  rest.
- **PEG error recovery/reporting** (Medeiros 2018/2019; "Towards Automatic
  Error Recovery in PEGs", 2025) — structured, position-carrying errors are
  the state of the art; parsanol's deepest-failure diagnostics + expected
  sets are the wire form the artifact format assumes (error wire-format
  decision: parsanol-rs#145).
- **Incremental parsing** (tree-sitter line; parsanol's retained-tree
  sessions) — grammars stay stable while edits reparse; PARG changes nothing
  here because artifacts are immutable data.
- **Bidirectionality** (render = parse in reverse) is the roadmap item PARG
  reserves envelope space for (`render:`/`derive:` sections — see
  pubid-grammar TODO/6 and parsanol-rs#144).

Prior art absorbed: ABNF/RFC 7405 (surface), ISO 14977 (import), RNC
(braced blocks, `#` comments), pest/PEG.js (import + predicate spelling),
tree-sitter/ANTLR (artifact compilation model), GrammarBuilder
(composition).

## Roadmap

- `render:` / `derive:` sections in the envelope (string output side).
- Multi-`[]`-level binding paths (or explicit binder hooks).
- Rule parameters / module imports between `.parg` files.
- Self-hosting: parse PARG with PARG.
- Export to constrained-decoding backends (XGrammar/llguidance formats).
