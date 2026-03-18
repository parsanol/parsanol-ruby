# Migration Guide: Parsanol 1.2.x → 1.3.0

## Overview

Version 1.3.0 brings a **simplified API** with lazy line/column support and removes deprecated parsing methods.

## Breaking Changes

### 1. Parsing Methods Unified

**Before (v1.2.x):**
```ruby
# Multiple confusing methods
Parsanol::Native.parse_parslet(grammar_json, input)
Parsanol::Native.parse_parslet_with_positions(grammar_json, input, cache)
Parsanol::Native.parse_with_transform(grammar_json, input, cache)
Parsanol::Native.parse_to_objects(grammar_json, input, type_map)
Parsanol::Native.parse_raw(grammar, input)
Parsanol::Native.parse_with_grammar(grammar, input)
```

**After (v1.3.0):**
```ruby
# One simple method
Parsanol::Native.parse(grammar, input)
```

### 2. Grammar Definition

**Before:**
```ruby
grammar = str('hello').as(:greeting)
grammar_json = Parsanol::Native.serialize_grammar(grammar)
result = Parsanol::Native.parse(grammar_json, 'hello')
```

**After:**
```ruby
grammar = str('hello').as(:greeting)
result = Parsanol::Native.parse(grammar, 'hello')
# No JSON serialization step needed!
```

### 3. Line/Column Computation

Line and column are now **lazy** — computed only when accessed.

**Before:**
```ruby
# Position cache was required upfront, added overhead
result = Parsanol::Native.parse_with_positions(grammar, input, cache)
slice = result[:greeting]
# Line/column computed immediately
```

**After:**
```ruby
result = Parsanol::Native.parse(grammar, input)
slice = result[:greeting]
# Line/column computed ONLY when accessed (lazy)
line, column = slice.line_and_column  # => [1, 1]
```

## Quick Reference

| Old Method | New Method |
|------------|------------|
| `parse_parslet(g, i)` | `parse(g, i)` |
| `parse_parslet_with_positions(g, i, c)` | `parse(g, i)` |
| `parse_with_transform(g, i, c)` | `parse(g, i)` |
| `parse_to_objects(g, i, m)` | `parse(g, i)` |
| `parse_raw(g, i)` | `parse(g, i)` |
| `parse_with_grammar(g, i)` | `parse(g, i)` |

## Complete Migration Example

### Before (v1.2.x)
```ruby
require 'parsanol/native'

# Define grammar
greeting = str('hello').as(:greeting)
grammar_json = Parsanol::Native.serialize_grammar(greeting)

# Parse with positions
cache = Parsanol::Source::LineCache.new
result = Parsanol::Native.parse_with_positions(grammar_json, "hello\nworld", cache)

# Access results
if result.success?
  slice = result[:greeting]
  puts slice.to_s           # => "hello"
  puts slice.offset         # => 0
  puts slice.line_and_column  # => [1, 1]
end
```

### After (v1.3.0)
```ruby
require 'parsanol/native'

# Define grammar
greeting = str('hello').as(:greeting)

# Parse — no JSON, no cache needed
result = Parsanol::Native.parse(greeting, "hello\nworld")

# Access results
if result
  slice = result[:greeting]
  puts slice.to_s           # => "hello"
  puts slice.offset         # => 0
  puts slice.line_and_column  # => [1, 1] (lazy!)
end
```

## Slice API Changes

### New `input` Attribute

Slices now expose the original input for lazy line/column computation:

```ruby
slice = result[:greeting]
slice.input        # => "hello\nworld"
slice.content      # => "hello"
slice.offset       # => 0
slice.line_and_column  # => [1, 1] (computed lazily)
```

### Removed Methods

| Removed | Use Instead |
|---------|-------------|
| `slice.position_cache` | `slice.input` |
| `slice.line_cache` | `slice.input` |

## JSON Grammar Support

If you have existing JSON grammars, they still work:

```ruby
# JSON grammar as string
result = Parsanol::Native.parse(json_string, input)

# Or Ruby grammar
result = Parsanol::Native.parse(str('hello'), 'hello')
```

## Performance Notes

- **Faster startup**: No need to serialize grammar on every parse
- **Zero overhead**: Line/column only computed when accessed
- **Cached grammars**: Repeated parses of the same grammar are fast

## Need Help?

- [GitHub Issues](https://github.com/parsanol/parsanol-ruby/issues)
- [Documentation](https://github.com/parsanol/parsanol-ruby#readme)
