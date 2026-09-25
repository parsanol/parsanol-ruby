# PG — the parsanol grammar language

*Programming guide and language reference. Version: 0.1 (this document
describes what ships in parsanol-ruby `Parsanol::PG` today).*

PG is a text language for writing parsanol grammars. One `.pg` file is the
**single source of truth** for a grammar: it compiles to a checksummed
**artifact** whose grammar section is the same portable JSON the native
engines (Ruby ext, FFI, wasm, Rust) register. Humans review the text;
machines consume the JSON; the checksum binds them together.

```
grammar.flavor.pg  ──compile──▶  artifact.json (portable grammar + bindings
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
# demo.pg
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

document = Parsanol::PG::Parser.new(File.read("demo.pg")).parse
result   = Parsanol::PG::Compiler.compile(document, tables_dir: "tables")
File.write("demo.artifact.json", JSON.generate(result.envelope))

artifact = Parsanol::PG::Artifact.load("demo.artifact.json")
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

`Parsanol::PG::Import.import(:abnf, text)` (also `:ebnf`, `:pest`) returns
PG source generated from a foreign grammar — commit the result and compile
it like hand-written PG.

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
| `x as name` | capture — names the parse result | `Named(name)` |

Repetition prefixes bind one primary: `3*(a b)` — parenthesize composites.
A capture binds the primary it follows: `dash number as part` captures
`number` only.

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

### Tables

`alt from_table` and `table_lookup` resolve `NAME.yaml` / `NAME.yml` /
`NAME.json` under the compile-time `tables_dir` (artifact consumers resolve
against the artifact's directory). A hash table becomes rows keyed by
`name`; an array table is rows as-is. Tables referenced by the grammar are
recorded in the artifact's `tables` manifest and shipped with it.

## Semantics

PG has **PEG semantics**: ordered choice, greedy repetition, no ambiguity.
There is no global ambiguity to report because first match wins — which is
exactly why the compile-time lint below exists.

**Left recursion is rejected at compile time** (direct and indirect,
leftmost-position analysis). An unguarded left-recursive PEG loops forever
in every engine; PG refuses to emit such an artifact.

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
  "source": "…the original .pg text…",
  "checksum": "sha256:…"
}
```

- `entries[].grammar` is the **portable Grammar JSON** — the exact format
  `parsanol-rs` (`Grammar::from_json`), the wasm surface, and the Ruby
  native extension register. One serialization, four engines.
- `source` embeds the PG text: an artifact is self-contained, and a Ruby
  runtime can recompile atoms without the original file.
- `checksum` = sha256 over the canonicalized envelope (sorted keys,
  checksum excluded). `Artifact.load` verifies it and **fails loudly on
  mismatch** — never silently falls back.
- Semver: capture renames/removals → major; new alternatives → minor;
  literal fixes → patch. `version` and `binding_version` move separately:
  model-side-only changes bump `binding_version`.

## Importing foreign grammars

`Parsanol::PG::Import.import(kind, text)` parses a foreign grammar and
returns equivalent **PG source** (self-checked by re-parsing). Commit the
result; the `.pg` file stays the single source of truth. Each importer
documents its semantic conversions in the emitted header.

### ABNF — RFC 5234 + RFC 7405 (`:abnf`)

| ABNF | PG |
|---|---|
| bare `"abc"` — **case-insensitive** | `%i"abc"` |
| `%s"abc"` (case-sensitive) | `"abc"` |
| `%x41-5A`, `%x0D.0A`, `%d13`, `%b1010` | `%x41-5A`, `%x0D %x0A`, `%x0d`, `%x0a` |
| `n*m`, `*x`, `3x`, `[x]`, `(...)`, `/` | same shapes |
| `rule =/ alt` (incremental) | merged into one alternative |
| rule names (case-insensitive, `-`) | lowercased, `-` → `_` |
| RFC 5234 core rules (ALPHA…) | emitted unless locally defined |
| `<prose-vals>` | **rejected** — not machine-parseable |

**The one deep semantic difference:** ABNF alternation is unordered; PG's
is ordered. The compile-time lint flags every order-dependent branch the
import produces, so mechanical transliterations become reviewable instead
of silently different.

### EBNF — ISO 14977 (`:ebnf`)

| ISO EBNF | PG |
|---|---|
| `"…"`, `'…'` terminals | exact strings |
| `,` sequence / `|` alternation | juxtaposition / `/` |
| `[x]` optional / `{x}` zero-or-more | `[ x ]` / `*( x )` |
| meta-identifiers (case-insensitive) | downcased |
| `term - exception` (syntactic exception) | `!( exception ) term` — exact when the exception matches a prefix of the term's match; each occurrence noted in the header |
| `? special sequences ?` | **rejected** |

### pest — Rust PEG (`:pest`)

| pest | PG |
|---|---|
| `\|`, `!`, `&`, `*`, `+`, `?` | direct (postfix → PG prefix/`[ ]`) |
| `"lit"` / `^"lit"` | `"lit"` / `%i"lit"` |
| `'a'..'z'` | `%x61-7a` |
| builtins (`ASCII_DIGIT`, `ASCII_ALPHA`, `ANY`, …) | `%x` ranges |
| `~` | sequence **plus a header note**: pest inserts implicit WHITESPACE there, PG does not — whitespace must be explicit |
| `_{ }` / `@{ }` / `${ }` modifiers, `name_` silent rules | accepted, noted; captures stay enabled |
| `PUSH/POP/PEEK/EOI/SOI`, `WHITESPACE`/`Comment` rules | **rejected** with an explanatory error |

## lutaml-model integration

PG artifacts are the **"serialization from string" path** of lutaml-model:
the grammar fills information models declared with lutaml-model's
attribute/mapping DSL. Registration goes through lutaml-model's own
`FormatRegistry` extension point:

```ruby
Parsanol::PG::Lutaml.register(
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

The recent research converges on exactly the primitives PG ships:

- **Grammar-constrained generation** (XGrammar, arXiv:2411.15100, 2024;
  XGrammar-2, 2026; llguidance/"Practical Grammar-Based Constrained
  Decoding", 2024) — treats *compiled, serialized grammar artifacts* as the
  interchange unit and precomputes context-independent structure. PG's
  checksummed artifact + portable grammar JSON is the same contract for
  parsers, and is the natural export target for constrained-decoding
  backends later.
- **PEG ordered choice as a hazard** ("PEGs Made Practical"; pegen's docs;
  community debates 2024) — silent shadowing is the recurring complaint.
  PG's first-set lint turns the two detectable classes (prefix shadowing,
  empty-matchable non-final branches) into build failures and records the
  rest.
- **PEG error recovery/reporting** (Medeiros 2018/2019; "Towards Automatic
  Error Recovery in PEGs", 2025) — structured, position-carrying errors are
  the state of the art; parsanol's deepest-failure diagnostics + expected
  sets are the wire form the artifact format assumes (error wire-format
  decision: parsanol-rs#145).
- **Incremental parsing** (tree-sitter line; parsanol's retained-tree
  sessions) — grammars stay stable while edits reparse; PG changes nothing
  here because artifacts are immutable data.
- **Bidirectionality** (render = parse in reverse) is the roadmap item PG
  reserves envelope space for (`render:`/`derive:` sections — see
  pubid-grammar TODO/6 and parsanol-rs#144).

Prior art absorbed: ABNF/RFC 7405 (surface), ISO 14977 (import), RNC
(braced blocks, `#` comments), pest/PEG.js (import + predicate spelling),
tree-sitter/ANTLR (artifact compilation model), GrammarBuilder
(composition).

## Roadmap

- `render:` / `derive:` sections in the envelope (string output side).
- Multi-`[]`-level binding paths (or explicit binder hooks).
- Rule parameters / module imports between `.pg` files.
- Self-hosting: parse PG with PG.
- Export to constrained-decoding backends (XGrammar/llguidance formats).
