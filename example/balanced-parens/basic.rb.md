# Balanced Parentheses - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/balanced-parens
ruby basic.rb
```

## Code Walkthrough

### Recursive Balanced Rule

Parentheses are defined recursively:

```ruby
rule(:balanced) {
  str('(').as(:l) >> balanced.maybe.as(:m) >> str(')').as(:r)
}
```

Each level contains opening paren, optional nested content, and closing paren.

### Labeled Components

Each part is labeled for pattern matching:

```ruby
str('(').as(:l)    # Opening paren labeled :l
balanced.maybe.as(:m)  # Middle content labeled :m
str(')').as(:r)    # Closing paren labeled :r
```

Labels enable precise pattern matching in transforms.

### Transform for Counting

The transform counts nesting depth:

```ruby
class Transform < Parsanol::Transform
  rule(:l => '(', :m => simple(:x), :r => ')') {
    x.nil? ? 1 : x+1
  }
end
```

Pattern matches the structure; nil indicates innermost level.

### Recursive Tree Structure

Deep nesting creates nested parse trees:

```ruby
# Input: ((()))
# Tree: {:l=>"(", :m=>{:l=>"(", :m=>{:l=>"(", :m=>nil, :r=>")"}, :r=>")"}, :r=>")"}
```

The innermost `:m` is nil when nothing is inside.

## Output Types

```ruby
# Parse tree for "(())":
{:l=>"(", :m=>{:l=>"(", :m=>nil, :r=>")"}, :r=>")"}

# After transform:
2  # Depth of nesting

# Invalid input:
# Raises Parsanol::ParseFailed
```

## Design Decisions

### Why Use Labels for Literals?

Labeling constant values (`:l => '('`) allows pattern matching on structure, not just values.

### Why Maybe for Middle Content?

The innermost parentheses have nothing inside. `.maybe` handles this base case.

### Why Count Depth in Transform?

Counting demonstrates tree traversal. Real applications might validate matching pairs or build AST structures.
