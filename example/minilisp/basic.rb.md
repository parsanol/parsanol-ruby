# Mini Lisp Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/minilisp
ruby basic.rb
```

## Code Walkthrough

### Expression Rule

S-expressions are recursively defined:

```ruby
rule(:expression) {
  space? >> str('(') >> space? >> body >> str(')') >> space?
}
```

Whitespace is optional around parentheses for flexible formatting.

### Body Rule

Body contains multiple expressions:

```ruby
rule(:body) {
  (expression | identifier | float | integer | string).repeat.as(:exp)
}
```

The repeat allows empty lists `()` and nested structures.

### Identifier Rule

Identifiers allow operator characters:

```ruby
rule(:identifier) {
  (match('[a-zA-Z=*]') >> match('[a-zA-Z=*_]').repeat).as(:identifier) >> space?
}
```

`=` and `*` are valid identifier chars for Lisp operators like `=` and `*`.

### Float Rule

Floats have decimal or exponent parts:

```ruby
rule(:float) {
  (
    integer >> (
      str('.') >> match('[0-9]').repeat(1) |
      str('e') >> match('[0-9]').repeat(1)
    ).as(:e)
  ).as(:float) >> space?
}
```

Captures the integer part and the exponent/fraction separately.

### String Rule

Strings handle escape sequences:

```ruby
rule(:string) {
  str('"') >> (
    str('\\') >> any |
    str('"').absent? >> any
  ).repeat.as(:string) >> str('"') >> space?
}
```

`str('\\') >> any` handles any escaped character including `\"`.

### Transform Class

Transforms convert parse trees to Ruby objects:

```ruby
class Transform
  t.rule(:identifier => simple(:ident)) { ident.to_sym }
  t.rule(:string => simple(:str))       { str }
  t.rule(:integer => simple(:int))      { Integer(int) }
  t.rule(:float=>{:integer=> simple(:a), :e=> simple(:b)}) { Float(a + b) }
  t.rule(:exp => subtree(:exp))         { exp }
end
```

`simple(:x)` matches single values; `subtree(:x)` matches nested structures.

## Output Types

```ruby
# Parse tree
{:exp=>[
  {:identifier=>"+"@s},
  {:integer=>"1"@s},
  {:integer=>"2"@s}
]}

# After transform
[:+, 1, 2]

# Nested expression
[:define, :test, [:lambda, [], [:begin,
  [:display, "something"],
  [:display, 1],
  [:display, 3.08]
]]]
```

## Design Decisions

### Why Symbol for Identifiers?

Ruby symbols are immutable and efficient for identifiers. They're commonly used for code representation.

### Why Float Assembly in Transform?

The float rule captures integer and exponent parts separately. The transform combines them into a Ruby Float.

### Why subtree for Expressions?

`subtree(:exp)` recursively transforms nested lists. This handles arbitrary nesting depth automatically.

### Why Separate Parser and Transform Classes?

Separation keeps grammar definition clean. The transform can evolve independently of parsing rules.
