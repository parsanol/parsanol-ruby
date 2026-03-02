# Error Demo - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/readme
ruby basic.rb
```

## Code Walkthrough

### Simple Parser Definition

A minimal parser that matches repeated 'a' characters:

```ruby
class MyParser < Parsanol::Parser
  rule(:a) { str('a').repeat }

  def parse(str)
    a.parse(str)
  end
end
```

The parser only accepts strings of 'a's.

### Successful Parse

When input matches the grammar:

```ruby
MyParser.new.parse('aaaa')
# => "aaaa"
```

Returns the matched string.

### Failed Parse

When input doesn't match:

```ruby
MyParser.new.parse('bbbb')
# => Parsanol::ParseFailed: Expected "a" at line 1, column 1
```

Raises an exception with error details.

### Error Reporting

Parslet provides rich error messages:

- What was expected
- Where the error occurred (line, column)
- What was found instead

## Output Types

```ruby
# Success:
"aaaa"

# Failure (raises exception):
# Parsanol::ParseFailed: Expected "a" at line 1, column 1
```

## Design Decisions

### Why This Example?

Demonstrates basic error handling behavior. Understanding errors is crucial for debugging parsers.

### Why Repeat?

`.repeat` allows zero or more matches. Empty string would also parse successfully.

### Ruby-Only Feature

This is a simple demonstration of Parslet-compatible error handling.
