# BENCHMARKS — parsanol vs the field

Status: **v1 (JSON corpus; five harnesses committed; the results table
was measured on a quiet host, and the pest/parslet/Ruby rows await a
rerun under the same conditions — see “Measurement conditions”)**.
Methodology + harnesses live in `benchmark/sota/`. Every number here is
reproducible from the committed harnesses.

## Methodology

- **Corpus**: seeded-generated RFC 8259 JSON documents
  (`corpora/json_inputs.json`): small 1.2 KB, medium 344 B, large
  83 KB (200-object array), wide 2.7 KB. Deterministic — every tool
  parses byte-identical inputs.
- **Pathological corpus** (`corpora/traps_inputs.json`): nine
  deterministic documents aimed at documented weak spots — 150-deep
  arrays and 100-deep objects (container/recursion cost), token-prefix
  near misses at volume, an escape storm, a 200 KB single string, a
  20k-element array, a 4k-key object, whitespace-heavy pretty-printing,
  and number-grammar edges. Every harness takes this file as its corpus
  argument, so the same protocol applies.
- **Grammar**: acceptance-only JSON (RFC 8259 with escapes), one
  equivalent grammar per tool:
  - parsanol: `json.parg` → compiled artifact → `PargArtifact::parse_shape`
    (the shipped artifact path; no bindings overhead)
  - pest: the canonical pest JSON example grammar (PEG, pair-tree
    construction)
  - Lark: the canonical Lark JSON grammar, `parser="lalr"`
  - tree-sitter: the official `tree-sitter-json` grammar
  - parslet: the legacy baseline parsanol replaced (pure Ruby, PEG)
  - parsanol Ruby API: the shipped artifact through the extension
    (`:native`) and through the bytecode VM with interpreter fallback
    (`:ruby`)
- **Protocol**: warmup + acceptance verification, then **median** of N
  iterations per document (N=50 here). Within a harness, documents are
  visited round-robin on each iteration. Tools run in one session;
  absolute milliseconds are host-load-sensitive, so only ratios within
  a session are meaningful.

## Measurement conditions

The table below was measured in a single quiet-host session (load
average < 2). Reruns must record the load average: on a contended host
(load > 50, other sessions) the same harnesses measured 2–7x slower,
non-uniformly across runtimes, which makes cross-tool comparison
meaningless. The pest, parslet, and Ruby-API harnesses were added after
that session and are **withheld from the table until they can be run
under the same quiet conditions** — publishing contended numbers next
to quiet ones would misrepresent the field.

## Results (2026-10-20, Apple M-series, median milliseconds)

| tool | small (1.2 KB) | medium (344 B) | wide (2.7 KB) | large (83 KB) |
|---|---|---|---|---|
| **tree-sitter** (C, ts-json) | 0.040 | 0.014 | 0.248 | **2.714** |
| **Lark** (python, LALR) | 0.443 | 0.156 | 2.975 | 34.070 |
| **parsanol-native** (Rust artifact path) | 1.680 | 0.534 | 5.841 | **184.808** |
| pest (rust, PEG) | pending | pending | pending | pending |
| parslet (ruby, legacy) | pending | pending | pending | pending |
| parsanol-ruby `:native` | pending | pending | pending | pending |
| parsanol-ruby `:ruby` (VM) | pending | pending | pending | pending |

## Honest reading

1. **tree-sitter is ~68x faster than parsanol-native on the large
   corpus.** Its parser is generated C with a hand-tuned
   error-tolerant core; ours is an interpreted VM over portable atoms.
   This is the clearest quantitative statement of the gap, and the
   motivation for the codegen direction (compile PARG to Rust source
   per grammar — the tree-sitter model) over interpretation.
2. **Lark-LALR beats parsanol-native ~5x on large.** Table-driven
   LALR on JSON-shaped grammars is simply a better algorithmic fit
   than backtracking PEG for this class; PEG pays for ordered choice
   and unlimited lookahead that JSON does not need.
3. **parsanol's differentiation is not raw JSON throughput** — it is
   the artifact/governance model (checksummed portable grammars,
   cross-engine conformance, provenance). The benchmark exists to keep
   that claim honest.

## Known gaps in this suite (open items)

- **Rerun all harnesses on a quiet host** and fill the pending rows
  (pest, parslet, parsanol-ruby `:native`/`:ruby`). Their harnesses are
  committed and acceptance-verified; only the timing run is pending.
- The pest failure tracked as #247 was a **harness grammar bug**, not a
  unicode issue: the inline form let `inner` swallow a bare quote as an
  "escape", so every object whose first key was a string failed. Fixed
  by the canonical `char = { !("\"" | "\\") ~ ANY | "\\" ~ escape }`
  shape; the harness now accepts every corpus document, including the
  non-ASCII large one.
- Corpora beyond JSON (pubid identifiers, asciichem, EXPRESS giants)
  remain — each needs an equivalent-grammar port per tool. The
  backtracking/pathological set is now committed as
  `corpora/traps_inputs.json`.
- **Deep nesting ceiling:** the portable engine's governor counts atom
  frames, so JSON arrays fail near ~198 nesting levels, surfacing as a
  misleading `expected ]` rather than a recursion-limit diagnostic. The
  trap corpus stays at 150 and the ceiling is tracked in parsanol-rs#260.
- The Ruby API path adds artifact-atom registration, result decoding,
  and flattening on top of the engine; the first (contended) readings
  suggest this layer dominates the large-document cost. That is a
  measurement to confirm on a quiet host before any optimization work.
- One machine, one run session; medians of 50. Reruns must record the
  machine and load average.

## Reproduce

    benchmark/sota/corpora/gen_json_corpus.rb              # corpus
    benchmark/sota/corpora/gen_trap_corpus.rb              # pathological corpus
    benchmark/sota/parsanol-harness <corpus> <artifact> N  # cargo run --release -- …
    benchmark/sota/pest-harness <corpus> N                 # cargo run --release -- …
    benchmark/sota/lark-harness/run_lark.py <corpus> N     # pip: lark
    benchmark/sota/ts-harness/run_ts.py <corpus> N         # pip: tree-sitter tree-sitter-json
    benchmark/sota/parslet-harness/run_parslet.rb <corpus> N
    benchmark/sota/ruby-harness/run_ruby.rb <artifact> <corpus> N

Each harness prints `tool,doc,bytes,iterations,median_ms` CSV lines.
Ruby harnesses run under `bundle exec`; the Python harnesses need the
dependencies above.
