# Non-Greedy Parsing Patterns - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/local
ruby basic.rb
```

## Code Walkthrough

### The Problem with Greedy Parsing

Traditional repetition is greedy and blind:

```ruby
a = str('a').repeat >> str('aa')
# Input: 'aaaa'
# Fails! repeat consumes all 'a's, leaving nothing for 'aa'
```

Greedy repetition takes as much as possible without considering what follows.

### Non-Blind Pattern

Transform the grammar to look ahead:

```ruby
# E1% E2 transformation:
# S = E2 | E1 S

def this(name, &block)
  Parsanol::Atoms::Entity.new(name, &block)
end
def epsilon
  any.absent?
end

a = str('a').as(:e) >> this('a') { a }.as(:rec) | epsilon
```

This recursively matches while checking alternatives.

### Greedy Non-Blind Alternative

Put the terminal first:

```ruby
b = str('aa').as(:e2) >> epsilon |
    str('a').as(:e1) >> this('b') { b }.as(:rec)
```

Try to match the end (`aa`) first, then recurse if that fails.

### Entity for Recursion

The `this()` helper enables recursive rule definition:

```ruby
def this(name, &block)
  Parsanol::Atoms::Entity.new(name, &block)
end
```

Entity delays evaluation until parse time, allowing forward references.

## Output Types

```ruby
# Greedy blind (fails):
a.parse('aaaa')  # => ParseFailed

# Greedy non-blind (succeeds):
b.parse('aaaa')
# => {:e2=>"aa"@0}
#    or with proper structure showing the match
```

## Design Decisions

### Why Transform Instead of Modify Parser?

Grammar transformation is more flexible than modifying the parser engine. Different transformations achieve different behaviors.

### Why Entity for Recursion?

Ruby blocks capture variables at definition time. Entity provides a way to reference rules that aren't defined yet.

### Ruby-Only Feature

These advanced PEG patterns use Parslet's Ruby-specific constructs. They demonstrate theoretical parsing concepts more than practical usage.
