# 3 — Make result materialization near-free

Status: PARTIAL (arena collapse done 2026-09-14; lazy slices/AST pending)

## 3.1 Arena input-ref collapse — DONE

`collapse_ast` in parsanol-rs `ffi/ruby/transform.rs` folds runs of adjacent
InputRefs in all-string sequences/repetitions into a single InputRef before
any Ruby object is built. This took the native path from ~2.5s to ~0.69s on
the 27KB AsciiChem workload and is the main reason native is ~10x the Ruby
path today.

## 3.2 Lazy Slice content — PENDING

`create_slice` currently materializes a Ruby substring per Slice. Post-
collapse token grammars produce few slices, but hash-heavy grammars (JSON,
calc) still create one per token.

Plan: let `Slice` hold `(input, offset, length)` with content computed
lazily on first `.content` (like the existing lazy `line_and_column`).
Additive constructor kwarg (`content: nil, content_length:`), Rust
`create_slice` passes offset/len only. Audit `Slice` consumers (pools,
BatchDecoder, user API) before flipping the default.

## 3.3 Lazy AST — PENDING (big)

Return an opaque handle + offsets table; materialize nodes on access.
Removes ~all materialization cost for consumers that read a few fields of a
large tree. Large effort: touches the whole result API. Do only if
profiling shows materialization dominating real consumers after 3.2.

## 3.4 Bulk API — EXISTS

`parse_batch` / `_parse_batch_raw` already cross FFI once per input set;
promote in docs when batch workloads appear.
