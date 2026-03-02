# Expression Evaluator - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/expression-evaluator
ruby basic.rb "1+2*3"
```

## Code Walkthrough

### Operator Precedence Hierarchy

The parser uses layered rules for precedence:

```ruby
rule(:expression) { comparison }
rule(:comparison) { addition >> (op >> addition).repeat | addition }
rule(:addition) { multiplication >> (op >> multiplication).repeat | multiplication }
rule(:multiplication) { power >> (op >> power).repeat | power }
rule(:power) { unary >> (str('^') >> power).maybe | unary }
```

Lower precedence operators are higher in the rule hierarchy. Comparison is tried first, falling through to addition, then multiplication, then power.

### Right Associativity for Exponentiation

Power uses `.maybe` for right associativity:

```ruby
rule(:power) {
  unary.as(:left) >>
  (str('^').as(:op) >> power.as(:right)).maybe |
  unary
}
```

Recursive reference to `power` on the right creates `2^(3^2)` instead of `(2^3)^2`.

### Unary Operators

Unary minus and logical not prefix expressions:

```ruby
rule(:unary) {
  (str('-').as(:op) >> unary.as(:operand)).as(:unary) |
  (str('!').as(:op) >> unary.as(:operand)).as(:unary) |
  primary
}
```

Recursive definition allows `--5` (double negation).

### Function Calls

Functions have name followed by parenthesized arguments:

```ruby
rule(:funcall) {
  (match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat).as(:name) >>
  lparen >>
  arglist.as(:args) >>
  rparen
}

rule(:arglist) {
  (expression >> (comma >> expression).repeat).maybe
}
```

Arguments are comma-separated expressions; empty arglists are valid.

### AST Node Classes

Ruby structs represent AST nodes with evaluation logic:

```ruby
BinaryOp = Struct.new(:left, :op, :right) do
  def eval(ctx)
    l = left.eval(ctx)
    r = right.eval(ctx)
    case op
    when '+' then l + r
    when '-' then l - r
    # ...
    end
  end
end
```

Each node type implements `eval(context)` for recursive evaluation.

### Evaluation Context

Context holds variables and functions:

```ruby
class EvalContext
  attr_accessor :variables, :functions

  def initialize
    @variables = { 'PI' => Math::PI, 'E' => Math::E }
    @functions = {
      'sin' => ->(args) { Math.sin(args[0] || 0) },
      'cos' => ->(args) { Math.cos(args[0] || 0) },
      # ...
    }
  end
end
```

Functions are Ruby lambdas that receive argument arrays.

## Output Types

```ruby
Number.new(42.0)                      # Numeric literal
Variable.new("x")                     # Variable reference
BinaryOp.new(Number.new(1), "+", Number.new(2))  # Binary operation
UnaryOp.new("-", Number.new(5))       # Unary negation
FunctionCall.new("sin", [Variable.new("x")])  # Function call
```

After `eval`: returns Float result.

## Design Decisions

### Why Layered Rules for Precedence?

Layered rules naturally express precedence in PEG parsers. Each layer only "sees" operators at its level, preventing incorrect bindings.

### Why Structs with eval Methods?

Structs are lightweight and can define instance methods. Embedding `eval` in each node enables clean recursive evaluation without visitor patterns.

### Why Lambda for Functions?

Ruby lambdas are first-class and can be stored in a hash. This allows easy extension of the function library without modifying the evaluator.
