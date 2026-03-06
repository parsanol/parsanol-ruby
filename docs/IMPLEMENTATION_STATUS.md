# Capture, Scope, Dynamic FFI Implementation - Status

**Date**: 2026-03-06
**Status**: COMPLETED

## Summary

Implemented FFI bindings for capture, scope, and dynamic atoms in parsanol-ruby, and updated the documentation website.

## Completed Work

### 1. parsanol-ruby (Ruby Repository)

#### Files Modified
| File | Change |
|------|--------|
| `README.adoc` | Added capture, scope, dynamic to API Compatibility Matrix and new documentation section |
| `ext/parsanol_native/src/lib.rs` | Updated import path to `parsanol::ffi::ruby::init` |
| `lib/parsanol/native/serializer.rb` | Added `serialize_capture`, `serialize_scope`, `serialize_dynamic` |
| `lib/parsanol/native/dynamic.rb` | NEW: Ruby callback registry and DynamicContext class |
| `lib/parsanol/native.rb` | Added require for dynamic module |
| `parsanol-rs/parsanol/src/ffi/ruby/dynamic.rs` | NEW: Rust FFI callbacks for Ruby |
| `parsanol-rs/parsanol/src/ffi/ruby/init.rs` | Added FFI export functions |
| `parsanol-rs/parsanol/src/ffi/ruby/mod.rs` | Updated exports |

#### Example Files Created
| Directory | Files |
|-----------|-------|
| `example/captures/` | `basic.rb`, `basic.rb.md`, `example.json` |
| `example/scopes/` | Updated `basic.rb`, `basic.rb.md`, `example.json` |
| `example/dynamic/` | `basic.rb`, `basic.rb.md`, `example.json` |
| `example/streaming-captures/` | `basic.rb`, `basic.rb.md`, `example.json` |

#### Test Results
- All 1178 tests pass
- Native extension compiles successfully
- Examples run correctly

### 2. parsanol.github.io (Website)

#### Files Modified
| File | Change |
|------|--------|
| `src/views/RubyBindings.vue` | Added capture, scope, dynamic to API Compatibility Matrix |

#### Verified Existing
- `src/views/examples/CapturesExample.vue` - Has Ruby code
- `src/views/examples/ScopesExample.vue` - Has Ruby code
- `src/views/examples/DynamicExample.vue` - Has Ruby code
- `src/views/examples/StreamingCapturesExample.vue` - Has Ruby code
- `src/views/CapturesGuide.vue` - Comprehensive guide exists
- `src/views/FeatureComparison.vue` - Feature comparison exists
- `src/data/examples-manifest.json` - All entries have `hasRuby: true`

#### Build Status
- Website builds successfully

## API Summary

### Ruby DSL

```ruby
# Capture atoms
atom.capture(:name)           # Capture matched text
result[:name]                 # Access captured value (Slice)
result[:name].to_s            # Convert to String

# Scope atoms
scope { inner_parser }        # Isolated capture context

# Dynamic atoms
dynamic { |ctx| parser }      # Runtime-determined parsing
ctx[:capture_name]            # Access captures in dynamic block
ctx.remaining                 # Remaining input from current position
ctx.pos                       # Current position
ctx.input                     # Full input string
```

### Rust FFI Functions

```rust
fn ruby_register_callback(callback_id: u64, description: String) -> u64;
fn ruby_unregister_callback(id: u64) -> bool;
fn ruby_get_callback_description(id: u64) -> Option<String>;
fn ruby_callback_count() -> usize;
fn ruby_clear_callbacks();
fn ruby_has_callback(id: u64) -> bool;
```

## Architecture

### Callback Flow

```
Ruby                          Rust
─────                         ─────
Dynamic.register(block)  ──►  register_callback(id, desc)
         │                         │
         │                         ▼
         │                  RubyDynamicCallback { id }
         │                         │
         ▼                         ▼
    parse()  ──────────────►  Parser::parse()
         │                         │
         │                    (on Dynamic atom)
         │                         │
         │                         ▼
         │                  callback.resolve(ctx)
         │                         │
         │                         ▼
         ◄─────────────────  invoke_from_rust(id, ctx)
         │                         │
         ▼                         │
    block.call(ctx)                │
         │                         │
         ▼                         │
    return atom  ──────────────►  ruby_value_to_atom()
                                   │
                                   ▼
                              ParseResult
```

## Backend Compatibility

| Feature | Packrat | Bytecode | Streaming |
|---------|---------|----------|-----------|
| Capture | Full | Full | Full |
| Scope | Full | Full | Full |
| Dynamic | Full | Packrat fallback | Packrat fallback |

## Performance Notes

- Captures: ~5% overhead for heavy use
- Scopes: ~2% per nesting level
- Dynamic: ~5-20% depending on callback complexity

## References

- Design document: `docs/CAPTURE_SCOPE_DYNAMIC_DESIGN.md` (in parsanol-rs)
- FFI documentation: `docs/FFI_CAPTURE_SCOPE_DYNAMIC.md`
- Migration guide: `docs/MIGRATION_EXPRESSIR.md`
