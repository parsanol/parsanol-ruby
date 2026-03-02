# Empty Rule Handling - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/empty
ruby basic.rb
```

## Code Walkthrough

### Empty Rule Definition

Rules can be defined without bodies:

```ruby
class MyParser < Parsanol::Parser
  rule(:empty) { }
end
```

This creates a rule placeholder without implementation.

### Error on Use

Calling an empty rule raises `NotImplementedError`:

```ruby
MyParser.new.empty.parslet
# => NotImplementedError: rule :empty not implemented
```

### Use Case: Grammar Sketching

Empty rules help sketch out grammar structure:

```ruby
class MyParser < Parsanol::Parser
  rule(:expression) { term >> (operator >> term).repeat }
  rule(:term) { }        # TODO: implement
  rule(:operator) { }    # TODO: implement
end
```

This lets you plan the structure before filling in details.

## Output Types

```ruby
# No parse output - raises error
NotImplementedError: rule :empty not implemented
```

## Design Decisions

### Why Allow Empty Rules?

Empty rules support incremental grammar development. They provide a way to stub out parts of a grammar.

### Why NotImplementedError?

Using `NotImplementedError` clearly indicates the issue is a missing implementation, not a parse error.

### Ruby-Only Feature

This is a Parslet-specific convenience for Ruby development. In Rust, you would use option types or placeholder patterns.

### When to Use

- Prototyping grammars
- Planning rule structure
- Documenting intended grammar layout
- Teaching parser concepts
