# Capture Atoms - Ruby Implementation

## How to Run

```bash
ruby example/captures/basic.rb
```

## Code Walkthrough

### Basic Setup

Create a grammar with captures, then parse:

```ruby
require 'parsanol/parslet'

# Simple capture
parser = str('hello').capture(:greeting)
result = parser.parse("hello world")
puts result[:greeting]  # => "hello"
```

### Email Parsing with Nested Captures

```ruby
email_parser = match('[a-zA-Z0-9._%+-]+').capture(:local) >>
                 str('@') >>
                 match('[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').capture(:domain)

result = email_parser.parse("user@example.com")
# => {:local => "user", :domain => "example.com"}
```

### Using Captures with Dynamic

```ruby
class CaptureParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:type) { match('[a-z]+').capture(:type) }
  rule(:value) do
    dynamic do |_source, context|
      case context.captures[:type]
      when 'int' then match('\d+')
      when 'str' then match('[a-z]+')
      end.capture(:value)
    end
  end
  rule(:declaration) { type >> str(':') >> match('[a-z]+').capture(:name) >> str('=') >> value }
  root :declaration
end

result = CaptureParser.new.parse("int:count=42")
# => {:type => "int", :name => "count", :value => "42"}
```

### Accessing Capture State

After parsing, access captures from the result:

```ruby
result = parser.parse(input)
result[:name]  # Access captured value
result.keys    # All capture names
```

## Output Types

### ParseResult

```ruby
result[:capture_name]  # Access captured value
result.keys            # All capture names
result.values          # All captured values
```

## Design Decisions

### Capture Persistence

Captures persist throughout the parse and are available in the result:

```ruby
# Captures from entire parse
result = parser.parse(input)
all_captures = result.keys
```

### Integration with Dynamic

Captures can be referenced in dynamic blocks:

```ruby
dynamic do |_source, context|
  captured = context.captures[:name]
  str(captured)  # Use captured value
end
```

## Performance Notes

| Metric | Value |
|--------|-------|
| Capture overhead | ~5% for heavy use |
| Lookup time | O(n) where n = number of captures |
| Memory per capture | Offset + length (zero-copy) |

**Optimization Tips**:

1. Use scopes to limit capture accumulation
2. Process captures incrementally for very large files
3. Capture only what you need

## Error Handling

```ruby
begin
  result = parser.parse(input)
  if result[:expected_capture]
    # Process capture
  end
rescue Parsanol::ParseFailed => e
  puts "Parse error: #{e}"
end
```
