# Nested Error Reporting - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/nested-errors
ruby basic.rb
```

## Code Walkthrough

### parse_with_debug Output

The debug method shows full error information:

```ruby
parser.parse_with_debug(input)
```

This automatically formats and displays the error tree.

### Error Tree Structure

Parslet errors form a tree:

```
- Failed to parse sequence
  - Expected "end" at line 3
  - In block body
    - Expected expression
    - Expected "begin"
```

Each indentation represents a nested failure context.

### Helper Formatting

The example provides line-numbered output:

```ruby
def prettify(str)
  puts " "*3 + " "*4 + "." + " "*4 + "10" + " "*3 + "." + " "*4 + "20"
  str.lines.each_with_index do |line, index|
    printf "%02d %s\n", index+1, line.chomp
  end
end
```

Column ruler helps locate errors visually.

### Complex Grammar for Testing

The example uses a realistic grammar:

```ruby
rule(:reference) {
  (str('@').repeat(1,2) >> identifier).as(:reference)
}

rule(:res_action_or_link) {
  str('.').as(:dot) >>
  (identifier >> str('?').maybe).as(:name) >>
  str('()')
}
```

Multiple rules create multiple failure points.

### Block Structure

Nested blocks create deep error trees:

```ruby
rule(:begin_block) {
  (str('concurrent').as(:type) >> space).maybe.as(:pre) >>
  str('begin').as(:begin) >>
  body >>
  str('end')
}

rule(:define_block) {
  str('define').as(:define) >> space >>
  identifier.as(:name) >> str('()') >>
  body >>
  str('end')
}
```

Each block type has its own error context.

### Test Cases

```ruby
ds = [
  %{
    define f()
      @res.name
    end
  },
  %{
    define f()
      begin
        @res.name
      end
    end
  }
]

ds.each do |d|
  puts '-' * 80
  prettify(d)
  parser.parse_with_debug(d)
end
```

Each case demonstrates different error scenarios.

## Output Types

Successful parse:
```
01
02 define f()
03   @res.name
04 end

{:define=>"define"@..., :name=>"f"@..., :body=>[...]}
```

Failed parse with tree:
```
01
02 define f()
03   @res.name(
04 end

Failed to match sequence
`- Expected ")" at line 3, column 12
```

## Design Decisions

### Why parse_with_debug?

It handles error formatting automatically. For production use, catch `Parsanol::ParseFailed` and format custom messages.

### Why Multiple Test Cases?

Different constructs fail differently. Multiple cases show the full error reporting capability.

### Why Prettify Helper?

Line numbers help users find errors in their input. The column ruler aids visual scanning.

### Why Block-Structured Grammar?

Simple grammars have shallow error trees. Block-structured grammars demonstrate nested error contexts.
