# Scope Handling - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/scopes
ruby basic.rb
```

## Code Walkthrough

### Scope Blocks

Scopes isolate captures:

```ruby
parser = str('a').capture(:a) >>
         scope { str('b').capture(:a) } >>
         dynamic { |s,c| str(c.captures[:a]) }
```

The outer capture of 'a' is shadowed by the inner scope's capture of 'b'.

### Shadowing Behavior

Inner scopes can shadow outer captures:

```ruby
# Outer scope captures :a => 'a'
str('a').capture(:a) >>
# Inner scope captures :a => 'b' (shadows outer)
scope { str('b').capture(:a) } >>
# After scope, :a still refers to inner capture
dynamic { |s,c| str(c.captures[:a]) }  # matches 'b'
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
# - dynamic matches 'b' (inner capture)

# Input: 'aaa'
# Would FAIL because:
# - 'a' captured as :a
# - scope captures 'a' as :a
# - dynamic matches 'a' (not 'b')
```

## Design Decisions

### Why Lexical Scoping?

Lexical scoping matches how variables work in most programming languages. Users can reason about capture visibility.

### Why Shadow Instead of Merge?

Shadowing prevents accidental capture conflicts. Explicit naming would be needed for merging.

### Ruby-Only Feature

Scope blocks are a Parslet-specific feature for managing capture context. The Rust implementation uses different patterns for similar functionality.
