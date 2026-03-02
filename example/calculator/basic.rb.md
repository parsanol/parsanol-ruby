# Calculator - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/calculator
ruby basic.rb "1+2*3"
```

## Code Walkthrough

### Left Associativity via Repetition

Addition uses repetition for left associativity:

```ruby
rule(:addition) {
  multiplication.as(:l) >> (add_op >> multiplication.as(:r)).repeat(1) |
  multiplication
}
```

The pattern `l >> (op >> r).repeat` creates left-associative chains like `((1+2)+3)`.

### Multiplication Rule

Multiplication has higher precedence:

```ruby
rule(:multiplication) {
  integer.as(:l) >> (mult_op >> integer.as(:r)).repeat(1) |
  integer
}
```

Multiplication is tried first in the addition rule, giving it higher precedence.

### Operator Rules

Operators capture their symbol:

```ruby
rule(:mult_op) { match['*/'].as(:o) >> space? }
rule(:add_op) { match['+-'].as(:o) >> space? }
```

The `:o` label marks the operator for transform matching.

### AST Node Classes

Ruby structs represent AST nodes:

```ruby
Int = Struct.new(:int) {
  def eval; self end
  def op(operation, other)
    left = int
    right = other.int
    Int.new(
      case operation
        when '+' then left + right
        when '-' then left - right
        when '*' then left * right
        when '/' then left / right
      end)
  end
}

Seq = Struct.new(:sequence) {
  def eval
    sequence.reduce { |accum, operation|
      operation.call(accum) }
  end
}

LeftOp = Struct.new(:operation, :right) {
  def call(left)
    left = left.eval
    right = self.right.eval
    left.op(operation, right)
  end
}
```

`Int` represents values; `Seq` represents expression chains; `LeftOp` represents binary operations.

### Transform Rules

Transform builds the AST:

```ruby
class CalcTransform < Parsanol::Transform
  rule(i: simple(:i)) { Int.new(Integer(i)) }
  rule(o: simple(:o), r: simple(:i)) { LeftOp.new(o, i) }
  rule(l: simple(:i)) { i }
  rule(sequence(:seq)) { Seq.new(seq) }
end
```

Pattern matching extracts components and constructs typed objects.

## Output Types

```ruby
Int.new(42)              # Integer value
LeftOp.new('+', Int.new(2))  # Binary operation
Seq.new([Int.new(1), LeftOp.new('+', Int.new(2))])  # Expression chain
```

After `eval`: returns `Int` with result value.

## Design Decisions

### Why Struct for AST Nodes?

Structs are lightweight, immutable, and can define methods. They're ideal for simple AST representation.

### Why `repeat(1)` for Operators?

`repeat(1)` requires at least one operator, distinguishing `1+2` from bare `1`. The alternative handles the base case.
