# Parsanol Performance Guide for Ruby

This guide shows how to use Parsanol for high-performance parsing in Ruby applications.

## Key Architecture Change: Position Info is Now Default

**All parse methods now return `Parsanol::Slice` objects with position information by default.**

You no longer need to use a special "slice mode" - every parse result includes:
- `offset` - byte position in original input
- `length` - length of the matched text
- `line` and `column` - 1-indexed position (when line cache is available)

```ruby
result = parser.parse("hello world", mode: :native)
name = result[:name]

name.to_s            # => "hello"
name.offset          # => 7
name.length          # => 5
name.line_and_column # => [1, 8]
```

## The 3 Approaches

| Approach | Description | Speed | Best For |
|----------|-------------|-------|----------|
| 1. Ruby | Pure Ruby parsing | 1x (baseline) | Debugging, prototyping |
| 2. Native | Rust parsing with Slice objects | ~20x | Production use (RECOMMENDED) |
| 3. JSON | Rust parsing, JSON output | ~20x | APIs, serialization |

All approaches return Slice objects with position info.

## Evidence-Based Benchmarks

These are **actual benchmark results** from Expressir parsing EXPRESS schemas (22KB file, 733 lines):

| Mode | Time | Speedup | Notes |
|------|------|---------|-------|
| Ruby | 3036 ms | 1x (baseline) | Pure Ruby parsing |
| Native | 153 ms | 19.9x faster | Rust parsing with Slice objects |

**Run `bundle exec ruby benchmark/run_all.rb --quick` to verify on YOUR machine.**

## Slice Objects

All parse results contain `Parsanol::Slice` objects that preserve source position:

```ruby
# Parse result
result = parser.parse("SCHEMA test;", mode: :native)
# => {:name => "test"@7}

# Access the slice
slice = result[:name]
slice.to_s     # => "test" (string content)
slice.offset   # => 7 (byte position)
slice.length   # => 4
slice.line_and_column  # => [1, 8] (line, column - 1-indexed)

# String comparison works
slice == "test"  # => true

# Extract from original source
slice.extract_from(input)  # => "test"
```

### JSON Output Format

When using JSON mode, position info is included inline:

```ruby
result = parser.parse("hello", mode: :json)
# => {
#   "name": {
#     "value": "hello",
#     "offset": 0,
#     "length": 5,
#     "line": 1,
#     "column": 1
#   }
# }
```

### Why Position Info Matters

For tools like linters, IDEs, and Expressir, source position tracking is essential:

1. **Error Reporting**: Show precise error locations with line/column
2. **Go-to-Definition**: Map parsed elements back to source locations
3. **Comment Attachment**: Attach remarks to AST nodes by position
4. **Source Extraction**: Get original text for any parsed element

## Approach Details

### Approach 1: Ruby (Baseline)

Pure Ruby parsing. Use for debugging grammar issues.

```ruby
require 'parsanol'

class JsonParser < Parsanol::Parser
  rule(:string) { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) }
  rule(:value) { string | number }
  root(:value)
end

parser = JsonParser.new
result = parser.parse('42', mode: :ruby)
# Speed: 1x (baseline) - 3036ms for 22KB EXPRESS schema
# Returns Slice objects with position info
```

### Approach 2: Native (RECOMMENDED)

Rust parses, returns Slice objects. Best for production.

```ruby
require 'parsanol'

class JsonParser < Parsanol::Parser
  rule(:string) { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) }
  rule(:value) { string | number }
  root(:value)
end

parser = JsonParser.new
result = parser.parse('42', mode: :native)
# Speed: ~20x faster - 153ms for 22KB EXPRESS schema
# Returns Slice objects with position info
```

### Approach 3: JSON

Rust parses, returns JSON with position info. Best for APIs.

```ruby
require 'parsanol'

class JsonParser < Parsanol::Parser
  rule(:string) { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) }
  rule(:value) { string | number }
  root(:value)
end

parser = JsonParser.new
result = parser.parse('42', mode: :json)
# Speed: ~20x faster
# Returns JSON with position info inline
```

## When to Use Which Approach

| Use This | When You Need |
|----------|---------------|
| Ruby | Debugging grammar issues, prototyping |
| Native | Production use - best balance of speed and features |
| JSON | APIs, serialization, cross-language interoperability |

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

### 1. Always use Native mode for production

```ruby
# 20x faster than Ruby mode
result = parser.parse(input, mode: :native)
```

### 2. Pre-compile grammar for repeated parsing

```ruby
# Grammar compilation happens on first parse
# For performance-critical code, pre-warm:
parser = MyParser.new
parser.parse('')  # Warm up grammar caching

# Now subsequent parses are even faster
```

### 3. Enable grammar optimization for complex grammars

```ruby
class MyParser < Parsanol::Parser
  optimize_rules!  # Simplifies quantifiers, sequences, choices
end
```

### 4. Use Parslet compatibility layer for migration

```ruby
# Drop-in replacement for existing Parslet code
require 'parsanol/parslet'  # Instead of require 'parslet'

# Your existing Parslet parser works unchanged
class ExistingParser < Parsanol::Parslet::Parser
  # ... existing rules ...
end

# Uses Native mode automatically with Slice support
```

## Slice API Reference

```ruby
class Parsanol::Slice
  # Core attributes
  def content       # String content
  def offset        # Byte offset in original input
  def length        # Length of the slice
  def line_and_column  # [line, column] tuple (requires line cache)

  # String compatibility
  def to_s          # Returns content
  def to_str        # Implicit string conversion
  def ==(other)     # Compares content with String or Slice

  # JSON serialization
  def to_json       # Returns { "value" => ..., "offset" => ..., ... }
  def as_json       # Returns hash with position info

  # Utility
  def to_span(input)  # Returns SourceSpan object
  def extract_from(input)  # Extracts content from original input
end
```

## Architecture Patterns

### Pattern 1: Simple Parser

For most parsing tasks, a single parser class with native mode is sufficient:

```ruby
class JsonParser < Parsanol::Parser
  rule(:string) { str('"') >> (str('\\') >> any | str('"').absent? >> any).repeat >> str('"') }
  rule(:number) { match('[0-9]').repeat(1) >> (str('.') >> match('[0-9]').repeat(1)).maybe }
  rule(:value) { string.as(:string) | number.as(:number) | object | array }
  rule(:pair) { string.as(:key) >> str(':') >> value.as(:value) }
  rule(:object) { str('{') >> (pair >> (str(',') >> pair).repeat).maybe.as(:pairs) >> str('}') }
  rule(:array) { str('[') >> (value >> (str(',') >> value).repeat).maybe.as(:elements) >> str(']') }

  root(:json) { object | array }
end

parser = JsonParser.new
result = parser.parse(input, mode: :native)
```

### Pattern 2: With Transform

For converting parse trees to AST:

```ruby
class ExpressParser < Parsanol::Parser
  rule(:schema) { str('SCHEMA') >> identifier.as(:name) >> str(';') }
  rule(:identifier) { match('[a-zA-Z]') >> match('[a-zA-Z0-9_]').repeat }
  root(:schema)
end

class ExpressTransform < Parsanol::Transform
  rule(name: simple(:n)) { SchemaNode.new(n.to_s, n.offset) }
end

parser = ExpressParser.new
result = parser.parse('SCHEMA my_schema;', mode: :native)
ast = ExpressTransform.new.apply(result)
# Position info preserved through transform
```

## Troubleshooting

### Native extension not available

```
LoadError: Native parser not available. Run `rake compile` to build.
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

### Line/column info not available

Line and column require a line cache. The parser builds this automatically when using `mode: :native`. If using lower-level APIs:

```ruby
line_cache = Parsanol::Source::LineCache.new
line_cache.scan_for_line_endings(0, input)
Parsanol::Native.parse(grammar_json, input, line_cache)
```
