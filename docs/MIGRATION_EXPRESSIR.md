# Migration Guide: Expressir to Parsanol 1.2

This guide helps the Expressir team migrate to the new Parsanol API where **position information is returned by default** and **capture/scope/dynamic atoms are now available**.

## Summary of Changes

| Before (Parsanol 1.0) | After (Parsanol 1.2) |
|-----------------------|----------------------|
| `parse_parslet_compatible` was the only way to get slices | All parse methods return `Slice` objects |
| Slices were optional, required special API | Slices are default, always included |
| No position info in JSON output | JSON includes `value`, `offset`, `length`, `line`, `column` |
| Manual AST construction required | Capture atoms for direct extraction |
| No way to isolate nested captures | Scope atoms for capture isolation |
| No context-sensitive parsing | Dynamic atoms for runtime decisions |

## New in 1.2: Capture, Scope, Dynamic Atoms

### Capture Atoms

Extract named values directly without building full AST:

```ruby
# Instead of building AST and transforming
rule(:identifier) { match('[a-zA-Z_]').repeat(1).as(:identifier) }

# Use capture for direct extraction
rule(:identifier) { match('[a-zA-Z_]').repeat(1).capture(:name) }

# Access in result
result = parser.parse(input, mode: :native)
result[:name]  # => Slice with position info
```

### Scope Atoms

Isolate captures in nested structures:

```ruby
# Each section's captures are isolated
rule(:section) do
  str('[') >> identifier.capture(:section_name) >> str(']') >>
  scope { kv_pairs.repeat(1) }  # key/value captures discarded on exit
end
```

### Dynamic Atoms

Runtime-determined parsing based on context:

```ruby
# Parse different value types based on declaration
rule(:value) do
  dynamic do |ctx|
    case ctx[:type].to_s
    when 'INTEGER' then integer_literal
    when 'STRING' then string_literal
    when 'BOOLEAN' then boolean_literal
    else any_value
    end.capture(:value)
  end
end
```

## The Key Change

**You no longer need `parse_parslet_compatible`.** The standard `parse` method now returns `Parsanol::Slice` objects with position information.

```ruby
# OLD (Parsanol 1.0) - needed special method for position info
result = Parsanol::Native.parse_parslet_compatible(grammar, input)
result[:name]  # => "hello" (plain string, no position)

# NEW (Parsanol 1.1) - position info is default
result = parser.parse(input, mode: :native)
result[:name]  # => "hello"@7 (Slice with offset 7)
```

## Migration Steps

### Step 1: Update Parse Calls

Replace any calls to `parse_parslet_compatible` with the standard `parse` method:

```ruby
# Before
result = Parsanol::Native.parse_parslet_compatible(parser.root, input)

# After
result = parser.parse(input, mode: :native)
```

### Step 2: Access Position Information

All string values in the parse result are now `Parsanol::Slice` objects:

```ruby
result = parser.parse("SCHEMA my_schema VERSION 1;", mode: :native)

# Access the value (works like a string)
result[:name].to_s  # => "my_schema"

# Access position information
result[:name].offset          # => 7 (byte position)
result[:name].length          # => 10
result[:name].line_and_column # => [1, 8] (1-indexed)

# String comparison still works
result[:name] == "my_schema"  # => true
```

### Step 3: Handle Source Extraction

Use the new `extract_from` method to get original source text:

```ruby
# Extract from original input
original_text = result[:name].extract_from(input)
# => "my_schema"
```

### Step 4: JSON Serialization (if needed)

JSON output now includes position information:

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

## Complete Example: EXPRESS Schema Parser

Here's a complete example showing how to use the new API for EXPRESS schema parsing:

```ruby
require 'parsanol'

class ExpressParser < Parsanol::Parser
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }

  rule(:identifier) { match('[a-zA-Z]') >> match('[a-zA-Z0-9_]').repeat }
  rule(:version) { match('[0-9]').repeat(1) }

  rule(:schema_decl) do
    str('SCHEMA') >> space >>
    identifier.as(:name) >> space? >>
    str(';')
  end

  root(:schema_decl)
end

# Parse with position info (default)
parser = ExpressParser.new
input = "SCHEMA my_schema ;"
result = parser.parse(input, mode: :native)

# Access results
name = result[:name]
puts "Name: #{name.to_s}"           # => "my_schema"
puts "Offset: #{name.offset}"        # => 7
puts "Line/Col: #{name.line_and_column}"  # => [1, 8]

# Extract original source
puts "Original: #{name.extract_from(input)}"  # => "my_schema"
```

## Slice API Reference

```ruby
class Parsanol::Slice
  # Core attributes
  attr_reader :content       # String content
  def offset                 # Byte offset in original input
  def length                 # Length of the slice
  def line_and_column        # [line, column] tuple (1-indexed)

  # String compatibility
  def to_s                   # Returns content as string
  def to_str                 # Implicit string conversion
  def ==(other)              # Compares content with String or Slice
  def size                   # Alias for length

  # JSON serialization
  def to_json                # Returns JSON with value, offset, length, line, column
  def as_json                # Returns hash with position info

  # Utility
  def to_span(input)         # Returns SourceSpan object
  def extract_from(input)    # Extracts content from original input
end
```

## Use Cases for Expressir

### 1. Source Code Extraction

```ruby
# Get original source text for any parsed element
def extract_source(node, input)
  node.extract_from(input) if node.is_a?(Parsanol::Slice)
end
```

### 2. Remark Attachment

```ruby
# Attach remarks to nodes based on position
def attach_remark(node, remark, remark_offset)
  if node.is_a?(Parsanol::Slice)
    # Check if remark is near this node
    if remark_offset >= node.offset && remark_offset <= node.offset + node.length
      node.remark = remark
    end
  end
end
```

### 3. Error Reporting

```ruby
# Report errors with precise location
def report_error(node, message)
  line, col = node.line_and_column
  "#{message} at line #{line}, column #{col}"
end
```

### 4. AST with Position Info

```ruby
# Build AST nodes that preserve position
class SchemaNode
  attr_accessor :name, :name_offset, :name_line, :name_column

  def initialize(slice)
    @name = slice.to_s
    @name_offset = slice.offset
    @name_line, @name_column = slice.line_and_column
  end
end
```

## Breaking Changes

### String Comparison

Code that explicitly checks for `String` type will break:

```ruby
# Before - worked because values were strings
if result[:name].is_a?(String)
  # ...
end

# After - use to_s or check for Slice
if result[:name].is_a?(Parsanol::Slice)
  # ...
end

# Or just use string comparison (works with both)
if result[:name] == "expected_value"
  # ...
end
```

### String Methods

Most string methods work via `to_s`:

```ruby
# These work
result[:name].upcase
result[:name].downcase
result[:name].match(/pattern/)

# For other methods, use to_s first
result[:name].to_s.gsub(/old/, 'new')
```

## Performance

The new API maintains the same performance characteristics:

| Mode | Speed |
|------|-------|
| Ruby | 1x (baseline) |
| Native | ~20x faster |

Position tracking adds negligible overhead since it was already being computed by the Rust parser.

## Troubleshooting

### "Line/column info requires a line cache"

This error occurs when using low-level APIs without a line cache:

```ruby
# Solution: Use the standard parse method which handles this automatically
result = parser.parse(input, mode: :native)
```

### Values not comparing equal to strings

Make sure you're using `==` not `eql?`:

```ruby
# Works - compares content
result[:name] == "hello"  # => true

# Doesn't work - checks type
result[:name].eql?("hello")  # => false (different types)
```

## EXPRESS-Specific Examples with New Features

### Using Captures for Schema Extraction

```ruby
class ExpressSchemaParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:identifier) { match('[a-zA-Z]') >> match('[a-zA-Z0-9_]').repeat }
  rule(:version) { match('[0-9]').repeat(1) }

  rule(:schema_decl) do
    str('SCHEMA') >> space >>
    identifier.capture(:schema_name) >> space? >>
    (str('VERSION') >> space >> version.capture(:schema_version)).maybe >>
    str(';')
  end

  root(:schema_decl)
end

parser = ExpressSchemaParser.new
result = parser.parse("SCHEMA my_schema VERSION 1;", mode: :native)

puts result[:schema_name].to_s        # => "my_schema"
puts result[:schema_name].offset      # => 7
puts result[:schema_version].to_s     # => "1"
```

### Using Scopes for Entity Attributes

```ruby
class ExpressEntityParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:attribute_name) { identifier.capture(:attr_name) }
  rule(:attribute_type) { identifier.capture(:attr_type) }
  rule(:attribute_decl) do
    attribute_name >> str(':') >> attribute_type >> str(';')
  end

  rule(:entity_body) do
    scope { attribute_decl.repeat(1) }  # Captures discarded on exit
  end

  rule(:entity_decl) do
    str('ENTITY') >> space >>
    identifier.capture(:entity_name) >> str(';') >>
    entity_body >>
    str('END_ENTITY') >> str(';')
  end

  root(:entity_decl)
end

# Only entity_name is captured, not individual attributes
result = parser.parse("ENTITY point; x: REAL; y: REAL; END_ENTITY;", mode: :native)
puts result[:entity_name].to_s  # => "point"
# result[:attr_name] is nil (discarded by scope)
```

### Using Dynamic for Type-Dependent Literals

```ruby
class ExpressLiteralParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:type_name) { identifier.capture(:literal_type) }

  rule(:literal_value) do
    dynamic do |ctx|
      case ctx[:literal_type].to_s.upcase
      when 'INTEGER' then match('\d+').capture(:literal_int)
      when 'REAL' then match('\d+(\.\d+)?').capture(:literal_real)
      when 'STRING' then str("'") >> match("[^']*").capture(:literal_string) >> str("'")
      when 'BOOLEAN' then (str('.T.') | str('.F.')).capture(:literal_bool)
      when 'LOGICAL' then (str('.T.') | str('.F.') | str('.U.')).capture(:logical)
      else match('\w+').capture(:literal_unknown)
      end
    end
  end

  rule(:typed_literal) do
    type_name >> str(':') >> literal_value
  end

  root(:typed_literal)
end

parser = ExpressLiteralParser.new

result = parser.parse("INTEGER:42", mode: :native)
puts result[:literal_int].to_s  # => "42"

result = parser.parse("STRING:'hello'", mode: :native)
puts result[:literal_string].to_s  # => "hello"
```

## Backend Compatibility

| Feature | Packrat | Bytecode | Streaming |
|---------|---------|----------|-----------|
| Capture | Full | Full | Full |
| Scope | Full | Full | Full |
| Dynamic | Full | Packrat fallback | Packrat fallback |

**Note**: Dynamic atoms fall back to Packrat backend when using Bytecode or Streaming. This may impact performance for grammars with many dynamic atoms.

## Questions?

If you encounter issues migrating, please open an issue at:
https://github.com/parsanol/parsanol-ruby/issues
