# Dynamic Atoms - Ruby Implementation

## How to Run

```bash
ruby example/dynamic/basic.rb
```

## Code Walkthrough

### Basic Dynamic Callback

```ruby
# Always returns the same parser
parser = dynamic { str('hello') }
result = parser.parse("hello world")
```

### Context-Sensitive Callback

```ruby
dynamic do |_source, context|
  remaining = context.remaining

  # Look at remaining input to detect context
  if remaining.start_with?('def ')
    str('def')
  elsif remaining.start_with?('lambda ')
    str('lambda')
  else
    str('function')
  end
end
```

### Position-Based Callback

```ruby
dynamic do |_source, context|
  pos = context.pos
  input_length = context.input.length

  if pos == 0
    # First position: keyword
    str('let') | str('const')
  elsif pos < input_length / 2
    # First half: identifier
    match('[a-zA-Z_][a-zA-Z0-9_]*')
  else
    # Second half: value
    match('\d+') | match('[a-z]+')
  end
end
```

### Capture-Aware Callback

```ruby
dynamic do |_source, context|
  type = context[:type]

  case type
  when 'int' then match('\d+')
  when 'str' then match('[a-z]+')
  when 'bool' then str('true') | str('false')
  end.capture(:value)
end
```

## DynamicContext Fields

```ruby
context.input      # Full input string
context.pos        # Current position in input
context.captures   # Hash of captured values
context.remaining  # Remaining input from current position
```

## Design Decisions

### Callback Signature

```ruby
dynamic do |_source, context|
  # context: Parsanol::Native::DynamicContext with pos, captures, input

  # Must return a parslet atom
  str('something') | match('pattern')
end
```

### When Callback is Invoked

Callbacks are invoked at parse time, not grammar construction time:

```ruby
# Grammar construction - callback NOT invoked yet
parser = dynamic { some_callback }

# Parse time - callback invoked
result = parser.parse(input)
```

## Performance Notes

| Metric | Value |
|--------|-------|
| Callback overhead | ~5% per dynamic atom |
| Fallback overhead | ~20% slower on non-Packrat backends |
| Recommended for | Context-sensitive parsing |

**Optimization Tips**:
1. Keep callbacks fast - avoid I/O
2. Cache expensive computations
3. Use with capture for type-driven parsing

## Error Handling

```ruby
dynamic do |_source, context|
  # Return nil to fail the parse
  nil  # Causes parse failure at this position

  # Or return a valid atom
  str('valid')
end
```

## Configuration-Driven Parsing

Parser behavior can be configured at runtime:

```ruby
class ConfigurableParser < Parsanol::Parser
  include Parsanol::Parslet

  attr_accessor :strict_mode

  rule(:identifier) do
    dynamic do |_source, _context|
      if @strict_mode
        match('[a-z][a-z0-9_]*')  # Strict: lowercase only
      else
        match('[a-zA-Z_][a-zA-Z0-9_]*')  # Lenient
      end
    end
  end
end

parser = ConfigurableParser.new
parser.strict_mode = true
result = parser.parse("lowercase")  # Works
# parser.parse("Uppercase")  # Fails
```

## Backend Compatibility

| Backend | Support | Notes |
|---------|---------|-------|
| Packrat | Full | Native support via FFI callback |
| Bytecode | Partial | Uses Packrat fallback |
| Streaming | Partial | Uses Packrat fallback |

## API Summary

```ruby
# Define a dynamic atom
dynamic do |source, context|
  context.pos           # Current position
  context.captures[:n]  # Access captured values
  context.input         # Full input string
  context.remaining     # Remaining input
  # Return a parslet atom
end

# Access captures in dynamic block
dynamic do |_source, context|
  value = context[:capture_name]
  # Use value to determine parsing
end
```
