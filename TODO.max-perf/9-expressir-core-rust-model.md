# 9. expressir-core: the EXPRESS model builder in Rust (P0, strategic)

## Answer to "does expressir-rs exist?"

No. Searched GitHub (`gh search repos expressir-rs` → none) and
crates.io (`expressir-rs`, `expressir_core` → 404). expressir-java
exists (lutaml/expressir-java); a Rust model layer does not. This item
proposes building it as `expressir-core` inside lutaml/expressir
(same pattern as the java port).

## Why (measured)

The giants are no longer parse-bound. With parsanol 1.3.34/0.7.x on
the SRL corpus:

| stage (aic 605 KB) | time | share |
|---|---:|---:|
| native parse (parsanol, one Rust call) | ~0.9 s | ~14% |
| Expressir model build (Ruby) | ~5.2 s | ~80% |
| boundary + hydration | ~0.3 s | ~5% |

The architecture the consumer wants is already in place — expressir
makes ONE native call (parse + AST hydration inside Rust), then
hydrates its model afterwards in Ruby (`Builder.build_with_remarks`).
The 80% stage is the target.

Even after the bucketed-index round (lutaml/expressir#363: selects
gone, builder CPU -19%), the remaining cost is lutaml-model object
construction + remark attachment in Ruby: ~100k model objects per
giant, each through `Serialize#initialize_attributes` and
`instance_variable_set` (41% GC in the residual profile).

## Design

**New crate `expressir-core` (Rust) in the lutaml/expressir
workspace**, depending on parsanol 0.7.x:

1. **Grammar**: reuse the EXPRESS grammar JSON that expressir already
   serializes for the native tier (~2,300 atoms) — load via
   `Grammar::from_json`, compile once, parse with the VM (linear
   fragments) / walker (backtracking-heavy) exactly like parsanol's
   own engine selection. No grammar re-authoring.
2. **Model structs**: port Expressir::Model::* to Rust
   (Repository, ExpFile, Schema, Entity, Attribute, WhereRule,
   Statements, Expressions, Remarks...) as plain serde-compatible
   structs with arena-backed spans — the parsanol AST walk maps onto
   them 1:1.
3. **Remark attachment + scope resolution in Rust**: port
   ScopeResolver/RemarkAttacher/NodePositionIndex — the bucketed
   indexes (start/end-line maps, span bands, identity owner maps)
   port directly; the WHERE-clause index and LineMap too.
4. **Boundary**: magnus-backed lazy facade — Ruby objects materialize
   only where consumers touch them (Formatter, Liquid drops,
   to_yaml), OR a batch-marshal fast path for the from_file contract.
   Contract: `Expressir::Express::Parser.from_file` returns an
   identical object graph (verified by the 140-file corpus dump
   equality + full spec suite).

## Phases

1. Model structs + AST→struct walk for declarations (schema/entity/
   type/function/procedure/rule heads). Gate: structural dump parity
   on the SRL corpus.
2. Statements/expressions + remarks. Gate: full Formatter output
   byte-parity.
3. Lazy Ruby facade; flip from_file to expressir-core behind a
   feature flag; measure. Target: giants ≤ 2 s end-to-end (10x on
   the original #52 numbers).
4. Optional: emit Lutaml XML/YAML directly from the Rust structs,
   removing Ruby materialization entirely for serialization
   consumers.

## Acceptance gates

- 140-file SRL corpus: Formatter output byte-identical.
- expressir spec suite green through the facade.
- Perf: ≥3x on the model-build stage; giants ≤ 2 s end-to-end.

## Status

Proposed (P0); implementation is expressir-repo work. The parsanol
prerequisites are all shipped: byte-identical VM/walker trees,
compile-once programs, Ractor-safe parse (TODO.max-perf/4).
