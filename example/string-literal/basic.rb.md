# String Literal Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/string-literal
ruby basic.rb
```

## Code Walkthrough

### String Literal Rule

Strings are quoted with escape support:

```ruby
rule :string do
  str('"') >>
  (
    (str('\\') >> any) |
    (str('"').absent? >> any)
  ).repeat.as(:string) >>
  str('"')
end
```

Escaped characters (including escaped quotes) are handled; otherwise quotes terminate.

### Integer Literal Rule

Integers are sequences of digits:

```ruby
rule :integer do
  match('[0-9]').repeat(1).as(:integer)
end
```

Simple repetition captures multi-digit numbers.

### Literal Alternation

Literals can be strings or integers:

```ruby
rule :literal do
  (integer | string).as(:literal) >> space.maybe
end
```

Order matters: try more specific patterns first.

### File-Level Grammar

Multiple literals separated by newlines:

```ruby
rule :literals do
  (literal >> eol).repeat
end

rule :eol do
  line_end.repeat(1)
end
```

Each line contains one literal definition.

### AST Node Classes

Ruby structs represent AST nodes:

```ruby
class Lit < Struct.new(:text)
  def to_s
    text.inspect
  end
end
class StringLit < Lit
end
class IntLit < Lit
  def to_s
    text
  end
end
```

Inheritance allows shared behavior with type-specific formatting.

### Transform Rules

Transform creates typed AST nodes:

```ruby
transform = Parsanol::Transform.new do
  rule(:literal => {:integer => simple(:x)}) { IntLit.new(x) }
  rule(:literal => {:string => simple(:s)}) { StringLit.new(s) }
end
```

Pattern matching on content type determines node class.

## Output Types

```ruby
# Parse tree:
[
  {:literal=>{:integer=>"42"@s}},
  {:literal=>{:string=>"hello world"@s}}
]

# After transform:
[IntLit.new("42"), StringLit.new("hello world")]
```

## Design Decisions

### Why Handle Escapes in Strings?

Real-world string literals support escape sequences. `\"` allows quotes inside strings.

### Why Separate StringLit and IntLit?

Type-specific classes enable different behavior (formatting, validation, evaluation).

### Why Read from File?

Demonstrates parsing external input, common in compiler frontends.
