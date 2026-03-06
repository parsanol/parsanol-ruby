# Scope Atoms - Ruby Implementation

## How to Run

```bash
ruby example/scopes/basic.rb
```

## Code Walkthrough

### Basic Scope Isolation

```ruby
# Without scope: last capture wins
parser = str('a').capture(:temp) >> str('b') >> str('c').capture(:temp)
result = parser.parse("abc")
result[:temp]  # => "c"

# With scope: inner capture is discarded
parser = str('prefix').capture(:outer) >>
         scope { str('inner').capture(:inner) } >>
         str('suffix').capture(:outer_end)

result = parser.parse("prefix inner suffix")
result[:inner]  # => nil (discarded)
result[:outer]  # => "prefix"
```

### Nested Scopes

```ruby
parser = str('L1').capture(:level) >> str(' ') >>
         scope {
           str('L2').capture(:level) >> str(' ') >>
           scope { str('L3').capture(:level) }
         }

result = parser.parse("L1 L2 L3")
result[:level]  # => "L1" (only outermost survives)
```

### INI Configuration Parsing

```ruby
class IniParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:section) { section_header >> scope { kv_pair.repeat(1) } }
end

# Each section's key/value captures are isolated
result = parser.parse("[database]\nhost=localhost\n\n[server]\nport=8080\n")
result.keys  # => [:section] (key/value discarded)
```

## Design Decisions

### Capture Isolation

Captures inside a scope are pushed onto a stack and popped on exit:

```ruby
scope {
  str('a').capture(:x)  # Pushed onto capture stack
}  # Popped on scope exit
```

### Memory Bounds

Memory for captures is bounded by scope depth:
```
memory = base_captures + sum(scope_captures)
```

For deeply nested structures, scopes prevent unbounded capture accumulation.

### Scope Stack

Scopes form a stack during parsing:
```ruby
# Scope depth 0
str('outer').capture(:a) >>
scope {
  # Scope depth 1
  str('inner').capture(:b) >>
  scope {
    # Scope depth 2
    str('deep').capture(:c)
  }
  # Back to depth 1, :c discarded
}
# Back to depth 0, :b discarded
```

## Performance Notes

| Metric | Value |
|--------|-------|
| Scope push/pop overhead | O(c_scope) captures |
| Per-nesting overhead | ~2% |
| Memory impact | Bounded by scope depth |

**Optimization Tips**:
1. Use scopes for repeated structures
2. Scope deeply nested parsing
3. Scope recursive rules

## Error Handling

```ruby
begin
  result = parser.parse(input)
rescue Parsanol::ParseFailed => e
  puts "Parse error: #{e}"
end
```

## Shadowing Behavior

Inner scopes can shadow outer captures:

```ruby
# Outer scope captures :a => 'a'
str('a').capture(:a) >>
# Inner scope captures :a => 'b' (shadows outer)
scope { str('b').capture(:a) } >>
# After scope, :a refers to outer capture again
dynamic { |s,c| str(c.captures[:a]) }  # matches 'a'
```

### Isolation Benefits

Scopes prevent capture pollution:

- Nested constructs don't interfere with outer captures
- Each level has its own namespace
- Cleanup is automatic when scope exits

## Output Types

```ruby
# Input: 'aba'
# Parses successfully because:
# - 'a' captured as :a in outer
# - 'b' captured as :a in inner scope (shadows)
# - After scope exits, :a is 'a' again
# - dynamic matches 'a'

# Input: 'abb'
# Would FAIL because:
# - 'a' captured as :a
# - scope captures 'b' as :a
# - After scope exits, :a is 'a' again
# - dynamic would try to match 'a', not 'b'
```

## Design Decisions

### Why Lexical Scoping?

Lexical scoping matches how variables work in most programming languages. Users can reason about capture visibility.

### Why Discard Instead of Merge?

Discarding prevents accidental capture conflicts. Explicit naming would be needed for merging.

### Ruby-Only Feature

Scope blocks are a Parslet-specific feature for managing capture context. The Rust implementation uses similar functionality through the scope atom.
