# Transform Patterns - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/seasons
ruby basic.rb
```

## Code Walkthrough

### Transform Class Structure

Each season is a separate transform class:

```ruby
class Spring < Parsanol::Transform
  rule(:stem => sequence(:branches)) {
    {:stem => (branches + [{:branch => :leaf}])}
  }
end
```

Different classes encapsulate different transformation behaviors.

### Sequence Pattern

`sequence(:x)` matches arrays of simple values:

```ruby
rule(:stem => sequence(:branches)) {
  {:stem => (branches + [{:branch => :leaf}])}
}
```

`branches` is bound to the array content.

### Subtree Pattern

`subtree(:x)` matches any nested structure:

```ruby
rule(:stem => subtree(:branches)) {
  new_branches = branches.map { |b| {:branch => [:leaf, :flower]} }
  {:stem => new_branches}
}
```

Recursively applies to children.

### Branch Pattern

Match and transform nested arrays:

```ruby
class Fall < Parsanol::Transform
  rule(:branch => sequence(:x)) {
    x.each { |e| puts "Fruit!" if e == :flower }
    x.each { |e| puts "Falling Leaves!" if e == :leaf }
    {:branch => []}
  }
end
```

Iterate over array contents while transforming.

### Composition

Multiple transforms are applied in sequence:

```ruby
def do_seasons(tree)
  [Spring, Summer, Fall, Winter].each do |season|
    tree = season.new.apply(tree)
  end
  tree
end
```

Each transform passes its output to the next.

## Output Types

```ruby
# Initial tree:
{:bud => {:stem => []}}

# After Spring:
{:bud => {:stem => [{:branch => :leaf}]}}

# After Summer:
{:bud => {:stem => [{:branch => [:leaf, :flower]}]}}

# After Fall:
{:bud => {:stem => [{:branch => []}]}}

# After Winter:
{:bud => {:stem => []}}
```

## Design Decisions

### Why Separate Transform Classes?

Each transform has a single responsibility. Separation makes transformations testable and reusable.

### Why sequence vs subtree?

`sequence` is for homogeneous arrays; `subtree` handles arbitrary nesting. Different patterns for different structures.

### Why Apply in Sequence?

Pipelining transforms creates complex behavior from simple pieces. Each step is easy to understand and debug.

### Ruby-Only Feature

Transform patterns are Parslet's Ruby DSL for AST manipulation. Rust uses pattern matching and visitor patterns instead.
