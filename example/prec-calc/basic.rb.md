# Precedence Calculator - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/prec-calc
ruby basic.rb
```

## Code Walkthrough

### Infix Expression Parser

Parslet's Infix helper simplifies precedence handling:

```ruby
rule(:expression) { infix_expression(integer,
  [mul_op, 2, :left],
  [add_op, 1, :right]) }
```

Each operator tuple specifies: operator rule, precedence level, and associativity.

### Operator Definitions

Operators are simple character matches:

```ruby
rule(:mul_op) { cts match['*/'] }
rule(:add_op) { cts match['+-'] }
```

`cts` (consume trailing space) is a helper that strips whitespace after atoms.

### Helper Methods

The `cts` and `infix` methods reduce repetition:

```ruby
def cts atom
  atom >> space.repeat
end
def infix *args
  Infix.new(*args)
end
```

These keep the grammar DRY and readable.

### Variable Assignment Rule

Assignments combine identifier with expression:

```ruby
rule(:variable_assignment) {
  identifier.as(:ident) >> equal_sign >> expression.as(:exp) >> eol
}
```

Labels (`:ident`, `:exp`) mark captures for transformation.

### Transform Rules

The interpreter transforms parse tree to values:

```ruby
rule(int: simple(:int)) { Integer(int) }
rule(l: simple(:l), o: /^\*/, r: simple(:r)) { l * r }
rule(l: simple(:l), o: /^\+/, r: simple(:r)) { l + r }
```

Regex patterns on `:o` distinguish operators in transform rules.

### Binding Context

Transform receives context for variable storage:

```ruby
rule(ident: simple(:ident), exp: simple(:result)) { |d|
  d[:doc][d[:ident].to_s.strip.to_sym] = d[:result]
}
```

The `doc:` parameter passes a hash for accumulating bindings.

## Output Types

```ruby
# Parse tree
[{:ident=>"a"@0, :exp=>{:int=>"1"@4}},
 {:ident=>"b"@8, :exp=>{:int=>"2"@12}},
 {:ident=>"c"@16, :exp=>{:l=>{:int=>"3"@20}, :o=>"*"@22, :r=>{:int=>"25"@24}}}]

# After transform (bindings)
{:a=>1, :b=>2, :c=>75}
```

## Design Decisions

### Why Infix Helper?

The `Infix` class encapsulates precedence climbing logic. Without it, you'd need multiple recursive rules with careful ordering.

### Why Regex in Transform?

Parslet's transform doesn't support operator-specific rules directly. Regex matching on the operator string provides clean separation.

### Why Pass Context to Transform?

Variable bindings need accumulation across statements. Passing a context hash enables this without global state.

### Why Right Associativity for Addition?

This example demonstrates both associativities. In practice, addition is typically left-associative; the right associativity here is for demonstration.
