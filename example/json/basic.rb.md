# JSON Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/json
ruby basic.rb
```

## Code Walkthrough

### Number Rule Definition

Numbers in JSON can be integers, floats, or scientific notation:

```ruby
rule(:number) {
  (
    str('-').maybe >> (
      str('0') | (match('[1-9]') >> digit.repeat)
    ) >> (
      str('.') >> digit.repeat(1)
    ).maybe >> (
      match('[eE]') >> (str('+') | str('-')).maybe >> digit.repeat(1)
    ).maybe
  ).as(:number)
}
```

The rule handles negative numbers, decimal points, and exponent notation like `1e24`.

### String Rule Definition

Strings support escape sequences with backslash:

```ruby
rule(:string) {
  str('"') >> (
    str('\\') >> any | str('"').absent? >> any
  ).repeat.as(:string) >> str('"')
}
```

The pattern `str('\\') >> any` matches any escaped character; `str('"').absent? >> any` matches non-quote characters.

### Array and Object Rules

Arrays and objects use recursive definitions:

```ruby
rule(:array) {
  str('[') >> spaces? >>
  (value >> (comma >> value).repeat).maybe.as(:array) >>
  spaces? >> str(']')
}

rule(:object) {
  str('{') >> spaces? >>
  (entry >> (comma >> entry).repeat).maybe.as(:object) >>
  spaces? >> str('}')
}
```

Both support nested structures through the recursive `value` rule.

### Value Rule

The value rule combines all JSON types:

```ruby
rule(:value) {
  string | number |
  object | array |
  str('true').as(:true) | str('false').as(:false) |
  str('null').as(:null)
}
```

Order matters: try specific types before generic ones.

### Transform Rules

The transformer converts parse tree to Ruby objects:

```ruby
rule(:string => simple(:st)) {
  st.to_s
}
rule(:number => simple(:nb)) {
  nb.match(/[eE\.]/) ? Float(nb) : Integer(nb)
}
rule(:null => simple(:nu)) { nil }
rule(:true => simple(:tr)) { true }
rule(:false => simple(:fa)) { false }
```

Pattern matching on tree labels produces typed Ruby values.

## Output Types

```ruby
# JSON values become native Ruby types:
String   # "hello" -> "hello"
Integer  # 42 -> 42
Float    # 3.14 -> 3.14
TrueClass  # true -> true
FalseClass # false -> false
NilClass   # null -> nil
Array    # [1,2,3] -> [1,2,3]
Hash     # {"a":1} -> {"a"=>1}
```

## Design Decisions

### Why Separate Parser and Transformer?

Parslet's two-stage model separates syntax (parsing) from semantics (transformation). This makes grammars reusable and transformations customizable.

### Why Pattern Matching in Transform?

Pattern matching on tree structure is more maintainable than manual tree traversal. Each rule handles one case, making bugs easier to isolate.
