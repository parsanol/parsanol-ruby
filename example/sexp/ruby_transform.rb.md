# S-Expression Parser - Ruby Implementation (Transform)

## How to Run

```bash
cd parsanol-ruby/example/sexp
ruby ruby_transform.rb
```

## Code Walkthrough

### S-Expression Structure

An S-expression is either a list or an atom:

```ruby
rule(:sexp) {
  list | atom
}
```

This recursive definition allows arbitrarily nested structures.

### List Rule

Lists are parenthesized elements:

```ruby
rule(:list) {
  str('(') >> elements >> str(')')
}

rule(:elements) {
  (sexp >> space?).repeat
}
```

Elements are separated by optional whitespace, allowing `(a b c)` or `(a  b    c)`.

### Atom Rule

Atoms are numbers or symbols:

```ruby
rule(:atom) {
  number | symbol
}

rule(:symbol) {
  match('[^\s\(\)]+')
}

rule(:number) {
  (
    str('-').maybe >>
    match('[0-9]').repeat(1) >>
    (str('.') >> match('[0-9]').repeat).maybe
  )
}
```

Symbols exclude whitespace and parentheses; numbers support negative and decimal.

### AST Node Classes

Typed classes represent the parsed structure:

```ruby
class SexpList < Sexp
  attr_reader :elements
  def to_s
    "(#{@elements.map(&:to_s).join(' ')})"
  end
end

class SexpSymbol < Sexp
  attr_reader :name
end

class SexpNumber < Sexp
  attr_reader :value
end
```

Each class has a meaningful `to_s` for debugging.

### AST Builder Function

A recursive function builds the AST:

```ruby
def build_ast(tree)
  return nil if tree.nil?

  if tree.is_a?(Parsanol::Slice)
    s = tree.to_s
    if s.match?(/^-?\d+(\.\d+)?$/)
      SexpNumber.new(s)
    else
      SexpSymbol.new(s)
    end
  elsif tree.is_a?(Array)
    elements = tree.map { |t| build_ast(t) }.compact
    SexpList.new(elements)
  # ...
  end
end
```

Pattern matching on tree type determines node construction.

## Output Types

```ruby
# Input: "(+ 1 (* 2 3))"
# AST:
#<SexpList @elements=[
  #<SexpSymbol @name="+">,
  #<SexpNumber @value="1">,
  #<SexpList @elements=[
    #<SexpSymbol @name="*">,
    #<SexpNumber @value="2">,
    #<SexpNumber @value="3">
  ]>
]>

# to_s output:
"(+ 1 (* 2 3))"
```

## Design Decisions

### Why Recursive AST Builder?

The parse tree has varied structure (Hash, Array, Slice). A recursive function handles all cases uniformly.

### Why Separate Number and Symbol Classes?

Different AST node types allow type-specific behavior (evaluation, formatting, analysis).

### Why Not Use Transform?

The tree structure varies; manual recursion provides more control than pattern-based transforms for this case.
