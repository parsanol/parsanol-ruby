# Parsanol Performance Guide for Ruby

This guide shows how to use Parsanol for high-performance parsing in Ruby applications.

## The 5 Approaches

Parsanol offers 5 different approaches for parsing in Ruby, each representing a different trade-off between flexibility and performance:

| Approach | Description | Speed | Best For |
|----------|-------------|-------|----------|
| 1. parslet-ruby | Pure Ruby parsing (baseline) | 1x | Compatibility, debugging |
| 2. parsanol-ruby | Parsanol Ruby backend | ~1x | Learning, prototyping |
| 3. parsanol-native (Batch) | Rust parsing, AST via u64 | ~20x | Need Ruby objects, good performance |
| 4. parsanol-native (ZeroCopy) | Direct FFI construction | ~25x | Maximum performance |
| 5. parsanol-native (ZeroCopy + Slice) | Zero-copy + source positions | ~29x | Linters, IDEs, Expressir (BEST) |

## Evidence-Based Benchmarks

These are **actual benchmark results** from Expressir parsing EXPRESS schemas (22KB file, 733 lines):

| Mode | Time | Speedup | Notes |
|------|------|---------|-------|
| Ruby (Parslet) | 3036 ms | 1x (baseline) | Pure Ruby parsing |
| Native Batch (u64) | 153 ms | 19.9x faster | AST via u64 array transfer |
| Native ZeroCopy (Slice) | 106 ms | 28.7x faster | Zero-copy with source positions |

**Run `bundle exec ruby benchmark/run_all.rb --quick` to verify on YOUR machine.**

## Slice Support (New)

The ZeroCopy + Slice mode preserves source position information:

```ruby
# Before (plain strings - no position info):
[{"word"=>"hello"}, " ", {"name"=>"world"}]

# After (Slice objects with position info):
[{"word"=>"hello"@0}, " "@5, {"name"=>"world"@6}]

# The @N notation shows the byte offset in the original input
# Parsanol::Slice is compatible with Parslet::Slice
```

### Why Slice Support Matters

For tools like linters, IDEs, and Expressir, source position tracking is essential:

1. **Error Reporting**: Show precise error locations with line/column
2. **Go-to-Definition**: Map parsed elements back to source locations
3. **Code Generation**: Generate output with source mappings

### Using Slice Mode

```ruby
require 'parsanol'

class JsonParser < Parsanol::Parser
  rule(:string) { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) }
  rule(:value) { string | number }
  root(:value)
end

parser = JsonParser.new

# Enable ZeroCopy + Slice mode
grammar_json = Parsanol::Native.serialize_grammar(parser.root)
result = Parsanol::Native.parse_to_objects(grammar_json, '42', slice: true)

# Result contains Slice objects with position info
```

## Approach Details

### Approach 1: parslet-ruby (Baseline)

Pure Ruby parsing using the original Parslet gem. Use for maximum compatibility.

```ruby
require 'parslet'

class JsonParser < Parslet::Parser
  rule(:string) { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) }
  rule(:value) { string | number }
  root(:value)
end

parser = JsonParser.new
result = parser.parse('42')
# Speed: 1x (baseline) - 3036ms for 22KB EXPRESS schema
```

### Approach 2: parsanol-ruby

Same performance as Parslet, but with Parsanol's API. Good for learning the DSL.

```ruby
require 'parsanol'

class JsonParser < Parsanol::Parser
  use_ruby_backend!  # Force Ruby backend

  rule(:string) { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) }
  rule(:value) { string | number }
  root(:value)
end

parser = JsonParser.new
result = parser.parse('42')
# Speed: ~1x (equivalent to Parslet)
```

### Approach 3: parsanol-native (Batch)

Rust parses, AST transferred via u64 array, Ruby reconstructs objects. Good balance.

```ruby
require 'parsanol'

class JsonParser < Parsanol::Parser
  use_rust_backend!  # Use Rust for parsing

  rule(:string) { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) }
  rule(:value) { string | number }
  root(:value)
end

parser = JsonParser.new
result = parser.parse('42')
# Speed: ~20x faster - 153ms for 22KB EXPRESS schema
# AST transferred via u64 array, reconstructed in Ruby
```

### Approach 5: parsanol-native (ZeroCopy + Slice) - RECOMMENDED

Everything happens in Rust with zero-copy and source position tracking. Fastest mode.

```ruby
require 'parsanol'

class JsonParser < Parsanol::Parser
  rule(:string) { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) }
  rule(:value) { string | number }
  root(:value)
end

parser = JsonParser.new

# Serialize grammar and use ZeroCopy + Slice mode
grammar_json = Parsanol::Native.serialize_grammar(parser.root)
result = Parsanol::Native.parse_to_objects(grammar_json, '42', slice: true)

# Speed: ~29x faster - 106ms for 22KB EXPRESS schema
# Zero-copy with source position tracking
# Slice objects are compatible with Parslet::Slice
```

## When to Use Which Approach

| Use This | When You Need |
|----------|---------------|
| parslet-ruby | Maximum Parslet compatibility, debugging grammar issues |
| parsanol-ruby | Learning Parsanol DSL, prototyping |
| parsanol-native (Batch) | Ruby objects with good performance, simple transformations |
| ZeroCopy + Slice | Maximum performance + source positions (linters, IDEs, Expressir) |

## Running Benchmarks

Verify performance yourself:

```bash
cd parsanol-ruby
bundle install
bundle exec rake compile

# Run quick benchmarks
bundle exec ruby benchmark/run_all.rb --quick

# Run all benchmarks
bundle exec ruby benchmark/run_all.rb
```

Benchmark results are saved to `benchmark/reports/` as JSON files.

## Performance Tips

### 1. Always use Rust backend for approaches 3-5

```ruby
class MyParser < Parsanol::Parser
  use_rust_backend!  # 20-29x faster
end
```

### 2. Use Slice mode when you need source positions

```ruby
# For linters, IDEs, Expressir - always use slice mode
result = Parsanol::Native.parse_to_objects(grammar_json, input, slice: true)
```

### 3. Enable grammar optimization for complex grammars

```ruby
class MyParser < Parsanol::Parser
  use_rust_backend!
  optimize_rules!  # Simplifies quantifiers, sequences, choices
end
```

### 4. Pre-compile grammar for repeated parsing

```ruby
# Grammar compilation happens on first parse
# For truly performance-critical code, pre-warm:
parser = MyParser.new
parser.parse('')  # Warm up grammar caching

# Now subsequent parses are even faster
```

### 5. Use Parslet compatibility layer for migration

```ruby
# Drop-in replacement for existing Parslet code
require 'parsanol/parslet'  # Instead of require 'parslet'

# Your existing Parslet parser works unchanged
class ExistingParser < Parsanol::Parslet::Parser
  # ... existing rules ...
end

# Uses Rust backend automatically with Slice support
```

## Architecture Patterns

### Pattern 1: Simple Parser

For most parsing tasks, a single parser class with the Rust backend is sufficient:

```ruby
class JsonParser < Parsanol::Parser
  use_rust_backend!

  rule(:string) { str('"') >> (str('\\') >> any | str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) >> (str('.') >> match('[0-9]').repeat(1)).maybe }
  rule(:value) { string.as(:string) | number.as(:number) | object | array }
  rule(:pair) { string.as(:key) >> str(':') >> value.as(:value) }
  rule(:object) { str('{') >> (pair >> (str(',') >> pair).repeat).maybe.as(:pairs) >> str('}') }
  rule(:array) { str('[') >> (value >> (str(',') >> value).repeat).maybe.as(:elements) >> str(']') }

  root(:json) { object | array }
end
```

### Pattern 2: With Slice Support

For tools that need source position tracking:

```ruby
class ExpressParser < Parsanol::Parser
  rule(:schema) { str('SCHEMA') >> identifier.as(:name) >> str(';') }
  rule(:identifier) { match('[a-zA-Z]') >> match('[a-zA-Z0-9_]').repeat }
  root(:schema)
end

parser = ExpressParser.new
grammar_json = Parsanol::Native.serialize_grammar(parser.root)

# Parse with slice support - preserves source positions
result = Parsanol::Native.parse_to_objects(grammar_json, input, slice: true)

# Access source positions
result[:name]  # => "my_schema"@7  (offset 7 in input)
```

## Troubleshooting

### Native extension not available

```
LoadError: Rust backend requested but native extension not available.
Run `rake compile` to build the extension.
```

Solution:
```bash
cd parsanol-ruby
bundle exec rake compile
```

### Slow first parse

The first parse compiles and caches the grammar. To pre-warm:

```ruby
parser = MyParser.new
parser.parse('')  # Warm up
# Now subsequent parses are fast
```

### Slice objects not appearing

Make sure you're using the `slice: true` option:

```ruby
# Wrong - returns plain strings
result = Parsanol::Native.parse_to_objects(grammar_json, input)

# Right - returns Slice objects
result = Parsanol::Native.parse_to_objects(grammar_json, input, slice: true)
```
