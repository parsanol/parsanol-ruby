# TODO: Ruby Bindings Update for parsanol-rs 0.4.0

**Status:** Completed
**Created:** 2026-03-18
**Updated:** 2026-03-18
**Target:** parsanol-ruby 1.3.0 / parsanol-rs 0.4.0

## Overview

This plan updates the Ruby bindings with:
- ✅ Lazy line/column computation in Slice objects
- ✅ Unified single `parse()` API
- ✅ Optional: `parse_json()` FFI function for JSON output (separate feature) - deferred

---

## Completed: Phase 0 - Lazy Line/Column & Single API

### 0.1 parsanol-rs Changes (DONE - PR #28)

**Branch:** `feat/lazy-line-column-slices`
**PR:** https://github.com/parsanol/parsanol-rs/pull/28

| File | Status | Change |
|------|--------|--------|
| `parsanol/src/ffi/ruby/parser.rs` | ✅ Done | Single `parse()` function |
| `parsanol/src/ffi/ruby/normalize.rs` | ✅ Done | Universal AST normalization, creates Slices with input ref |
| `parsanol/src/ffi/ruby/init.rs` | ✅ Done | Clean exports |
| `parsanol/src/ffi/ruby/mod.rs` | ✅ Done | Updated module structure |
| `README.md` | ✅ Done | Updated Ruby FFI section |
| `parsanol/Cargo.toml` | ✅ Done | Fixed magnus version alignment (0.8.2 → git 0.9) |
| `normalize.rs` | ✅ Done | Fixed push(&item) → push(item) for magnus 0.9 API |

### 0.2 parsanol-ruby Changes (DONE - PR #7)

**Branch:** `feat/lazy-line-column-slices`
**PR:** https://github.com/parsanol/parsanol-ruby/pull/7

| File | Status | Change |
|------|--------|--------|
| `lib/parsanol/slice.rb` | ✅ Done | Lazy `line_and_column` with caching, supports String/LineCache |
| `lib/parsanol/native.rb` | ✅ Done | Clean API: `parse`, `serialize_grammar`, `parse_with_grammar` |
| `lib/parsanol/native/parser.rb` | ✅ Done | Matching clean API |
| `lib/parsanol/version.rb` | ✅ Done | Bumped to 1.3.0 |

### 0.3 Tests (DONE)

| File | Status | Change |
|------|--------|--------|
| `spec/native/parser_spec.rb` | ✅ Done | New tests for Native API |
| `spec/parsanol/slice_spec.rb` | ✅ Done | Updated for lazy line/column API |
| `spec/parsanol/options/zero_copy_spec.rb` | ✅ Done | Updated to use parse() |
| `spec/parsanol/pools/slice_pool_spec.rb` | ✅ Done | Updated for input string approach |
| `spec/integration/string_view_integration_spec.rb` | ✅ Done | Updated for new API |
| `spec/integration/rope_stringview_integration_spec.rb` | ✅ Done | Updated for new API |

### 0.4 PR Created

**Ruby PR:** https://github.com/parsanol/parsanol-ruby/pull/7
**Rust PR:** https://github.com/parsanol/parsanol-rs/pull/28

---

## Test Results

- **1108 tests passing** across unit, integration, acceptance, and native specs
- Native extension compiles and loads successfully
- All breaking changes tested

---

This is a **separate feature** for interoperability. Can be done in a follow-up PR.

### 2.1 Add `parse_json` to Rust FFI

**File:** `parsanol/src/ffi/ruby/parser.rs`

```rust
/// Parse input and return JSON-serialized AST
pub fn parse_json(grammar_json: String, input: String) -> Result<String, Error> {
    // ... implementation
}
```

### 2.2 Add JSON serialization helper

**File:** `parsanol/src/ffi/ruby/json.rs` (new file)

### 2.3 Add Ruby wrapper

**File:** `lib/parsanol/native.rb`

```ruby
def parse_json(grammar_json, input)
  Parser.parse_json(grammar_json, input)
end
```

---

## Version Alignment

| parsanol-ruby | parsanol-rs | Key Features |
|---------------|-------------|--------------|
| 1.0.x         | 0.1.x       | Core parsing, native extension |
| 1.1.x         | 0.2.x       | Slice support, streaming parser |
| 1.2.x         | 0.3.x       | Captures, scopes, dynamic atoms |
| **1.3.0**     | **0.4.0**   | Lazy line/column, unified `parse()` API |

---

## Implementation Checklist

### Phase 0: Lazy Line/Column (Completed)

- [x] parsanol-rs: Add `normalize.rs` module
- [x] parsanol-rs: Simplify `parser.rs` to single `parse()` function
- [x] parsanol-rs: Update `init.rs` exports
- [x] parsanol-rs: Update README
- [x] parsanol-rs: Create PR #28
- [x] parsanol-rs: Fix magnus version alignment
- [x] parsanol-rs: Fix normalize.rs push() API
- [x] parsanol-ruby: Update `slice.rb` with lazy line/column
- [x] parsanol-ruby: Simplify `native.rb` API
- [x] parsanol-ruby: Simplify `parser.rb` API
- [x] parsanol-ruby: Create PR #7
- [x] parsanol-ruby: Update tests
- [x] parsanol-ruby: Update version to 1.3.0
- [x] Build and verify native extension
- [x] Run full test suite (1108 tests passing)

### Phase 1: Tests (Completed)

- [x] Add tests for new `parse()` API
- [x] Add tests for lazy line/column
- [x] Update tests for deprecated methods
- [x] Update integration tests for new API

### Phase 2: parse_json (Deferred)

- [ ] Add `parse_json` to Rust FFI
- [ ] Create `json.rs` module
- [ ] Add Ruby wrapper
- [ ] Add tests
- [ ] Update documentation

---

## Breaking Changes

The following methods are removed in 1.3.0:

| Removed Method | Replacement |
|----------------|-------------|
| `parse_parslet(g, i)` | `parse(g, i)` |
| `parse_parslet_with_positions(g, i, cache)` | `parse(g, i)` |
| `parse_with_transform(g, i, cache)` | `parse(g, i)` |
| `parse_to_objects(g, i, map)` | `parse(g, i)` |
| `parse_raw(atom, i)` | `parse_with_grammar(atom, i)` |

---

## Notes

- Lazy line/column is the main feature of 0.4.0
- `parse_json` is deferred to keep the PR focused
- The Slice class now requires input string for line/column computation
- All old parsing methods map to the new `parse()` internally
