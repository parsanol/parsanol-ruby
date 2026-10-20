# BENCHMARKS — parsanol vs the field

Status: **v1 (JSON corpus, 3 of 4 harnesses; pest WIP)**.
Methodology + harnesses live in `benchmark/sota/`. Every number here is
reproducible from the committed harnesses.

## Methodology

- **Corpus**: seeded-generated RFC 8259 JSON documents
  (`corpora/json_inputs.json`): small 1.2 KB, medium 344 B, large
  83 KB (200-object array), wide 2.7 KB. Deterministic — every tool
  parses byte-identical inputs.
- **Grammar**: acceptance-only JSON (RFC 8259 with escapes), one
  equivalent grammar per tool:
  - parsanol: `json.parg` → compiled artifact → `PargArtifact::parse_shape`
    (the shipped artifact path; no bindings overhead)
  - pest: the canonical pest JSON example grammar (LALR-free PEG)
  - Lark: the canonical Lark JSON grammar, `parser="lalr"`
  - tree-sitter: the official `tree-sitter-json` grammar
- **Protocol**: interleaved round-robin (tool → doc → iteration) to
  spread load/thermal effects; **median** of N iterations reported
  (N=50 here); warmup + acceptance verification before timing. Per the
  house laws: no sequential A/B, no tiny-input-only ratios.

## Results (2026-10-20, Apple M-series, median milliseconds)

| tool | small (1.2 KB) | medium (344 B) | wide (2.7 KB) | large (83 KB) |
|---|---|---|---|---|
| **tree-sitter** (C, ts-json) | 0.040 | 0.014 | 0.248 | **2.714** |
| **Lark** (python, LALR) | 0.443 | 0.156 | 2.975 | 34.070 |
| **parsanol-native** (artifact path) | 1.680 | 0.534 | 5.841 | **184.808** |
| pest (rust, PEG) | WIP | WIP | WIP | WIP |

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

- **pest**: the harness fails on non-ASCII strings in the large corpus
  (`inner`/`ANY` unicode handling under investigation); harness
  committed, results withheld until fixed.
- Corpora beyond JSON (pubid identifiers, asciichem, EXPRESS giants,
  backtracking traps) are the next iteration — each needs an
  equivalent-grammar port per tool.
- VM (Ruby bytecode) numbers pending; the native artifact path is the
  shipped fast path.
- One machine, one run session; medians of 50. Reruns should pin the
  machine and load.

## Reproduce

    benchmark/sota/corpora/gen_json_corpus.rb          # corpus
    benchmark/sota/parsanol-harness                    # cargo run --release
    benchmark/sota/pest-harness                        # cargo run --release (WIP)
    benchmark/sota/lark-harness/run_lark.py            # pip: lark
    benchmark/sota/ts-harness/run_ts.py                # pip: tree-sitter tree-sitter-json

Each harness prints `tool,doc,bytes,iterations,median_ms` CSV lines.
