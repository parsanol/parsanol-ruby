# 1 — Kill the per-call FFI boundary tax (MRI native path)

Status: DONE (2026-09-14)

## Problem

A native parse of a ~10-char input costs ~12µs end to end, of which the pure
Rust parse is ~1–2µs. The rest is boundary cost paid on EVERY call, even when
the grammar is unchanged:

1. Grammar JSON re-marshal: `parse(grammar_json: String, ...)` converts the
   Ruby JSON string into an owned Rust `String` (copy) and re-hashes it with
   ahash to find the Rust-side LRU grammar cache.
2. Input copy: `input: String` param conversion validates + copies the input
   instead of borrowing `&str` from the Ruby string.
3. Grammar identity lookups on the Ruby side were already O(1) per parse
   (`GRAMMAR_HASH_CACHE[obj_id] ||=` memoizes the tree walk), so no work was
   needed there — the cost is purely the marshal/hash on the Rust boundary.

## Changes

- parsanol-rs `ffi/ruby`:
  - `register_grammar(json) -> u64 handle` — parse once, store
    `Arc<Grammar>` in a handle table (no per-parse `Grammar` clone, unlike
    the LRU `get().clone()` path).
  - `parse_handle(handle, input)` — takes the input as a borrowed `RString`
    (`as_str`, zero copy) when the grammar has **no Dynamic atoms**; falls
    back to an owned copy when it does (Dynamic callbacks re-enter Ruby and
    could in principle trigger compaction, making a borrow unsafe).
  - `release_grammar(handle)`, and `clear_grammar_cache` also drops handles.
- parsanol-ruby:
  - `Native.parse(atom, input)` resolves a handle through
    `HANDLE_CACHE[structure_hash]` (content-keyed, so stale `object_id`s
    cannot alias a different grammar) and calls `_parse_handle`.
  - Unknown-handle errors fall back to re-registration.
  - Pre-serialized JSON-string grammars keep the `_parse_raw` path.

## Expected / measured impact

- Small-input native path: fewer allocations + no JSON copy + no ahash per
  call (~1.5–2.5µs/call saved). See `benchmark/` before/after.
- Large inputs barely move (engine-bound already).

## Risks

- Handle table is process-global; cleared by `clear_grammar_cache` (same
  semantics as the old LRU).
- Borrowed input is safe on CRuby: GC does not move objects unless
  `GC.compact` runs; guarded by the no-Dynamic check.
