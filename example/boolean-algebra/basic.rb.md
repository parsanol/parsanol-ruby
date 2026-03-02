# Boolean Algebra - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/boolean-algebra
ruby basic.rb
```

## Code Walkthrough

### Variable Rule

Variables are `var` followed by digits:

```ruby
rule(:var) { str("var") >> match["0-9"].repeat(1).as(:var) >> space? }
```

The `.as(:var)` captures the numeric suffix for later use.

### Operator Precedence

AND binds tighter than OR through rule ordering:

```ruby
rule(:and_operation) {
  (primary.as(:left) >> and_operator >> and_operation.as(:right)).as(:and) |
  primary
}

rule(:or_operation) {
  (and_operation.as(:left) >> or_operator >> or_operation.as(:right)).as(:or) |
  and_operation
}
```

OR calls AND first, giving AND higher precedence.

### Parentheses Handling

Primary handles grouping:

```ruby
rule(:primary) { lparen >> or_operation >> rparen | var }
```

Parenthesized expressions recurse back to the top-level OR rule.

### DNF Transform

The transform converts to Disjunctive Normal Form:

```ruby
class Transformer < Parsanol::Transform
  rule(:var => simple(:var)) { [[String(var)]] }

  rule(:or => { :left => subtree(:left), :right => subtree(:right) }) do
    (left + right)
  end

  rule(:and => { :left => subtree(:left), :right => subtree(:right) }) do
    res = []
    left.each do |l|
      right.each do |r|
        res << (l + r)
      end
    end
    res
  end
end
```

OR concatenates alternatives; AND creates all combinations.

### DNF Output Structure

Arrays of arrays represent the formula:

```ruby
# var1 and (var2 or var3)
# => [["1", "2"], ["1", "3"]]
# Means: (var1 AND var2) OR (var1 AND var3)
```

## Output Types

```ruby
# Parse tree for "var1 and (var2 or var3)":
{:and=>{:left=>{:var=>"1"}, :right=>{:or=>{:left=>{:var=>"2"}, :right=>{:var=>"3"}}}}}

# After transform (DNF):
[["1", "2"], ["1", "3"]]
```

## Design Decisions

### Why Right Recursion?

Right recursion naturally handles left-to-right parsing while building the correct tree structure.

### Why DNF Output?

DNF is useful for query optimization and database searches. Each inner array is a conjunction that must all be true.

### Why subtree Instead of simple?

`subtree(:x)` matches any tree structure, allowing recursive matching of nested AND/OR operations.
