# Deepest Error Reporting - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/deepest-errors
ruby basic.rb
```

## Code Walkthrough

### Error Reporter Configuration

Parslet provides different error reporters:

```ruby
parser.parse_with_debug(input,
  :reporter => Parsanol::ErrorReporter::Deepest.new)
```

The `Deepest` reporter finds the point where parsing progressed furthest.

### Helper for Display

Format input with line numbers:

```ruby
def prettify(str)
  puts " "*3 + " "*4 + "." + " "*4 + "10" + " "*3 + "." + " "*4 + "20"
  str.lines.each_with_index do |line, index|
    printf "%02d %s\n", index+1, line.chomp
  end
end
```

This helps users locate errors in their input.

### Complex Grammar

The example uses a realistic grammar with multiple constructs:

```ruby
rule(:define_block) {
  str('define').as(:define) >> space >>
  identifier.as(:name) >> str('()') >>
  body >>
  str('end')
}

rule(:begin_block) {
  (str('concurrent').as(:type) >> space).maybe.as(:pre) >>
  str('begin').as(:begin) >>
  body >>
  str('end')
}
```

Multiple block types demonstrate error scenarios.

### Reference Parsing

Resources use dot notation:

```ruby
rule(:reference) {
  (str('@').repeat(1,2) >> identifier).as(:reference)
}

rule(:res_action_or_link) {
  str('.').as(:dot) >> (identifier >> str('?').maybe).as(:name) >> str('()')
}
```

Single `@` for reference, `@@` for class reference.

### Body Structure

Bodies contain nested content:

```ruby
rule(:body) {
  (line_separator >> (block | expression)).repeat(1).as(:body) >>
  line_separator
}
```

Recursion allows arbitrarily nested blocks.

### Testing with Errors

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
  parser.parse_with_debug(d, :reporter => Parsanol::ErrorReporter::Deepest.new)
end
```

Each test case shows how errors are reported.

## Output Types

```
01
02 define f()
03   @res.name
04 end

Parsed successfully
```

Or for errors:

```
01
02 define f()
03   @res.name(
04 end

Expected ')' at line 3, column 12
```

## Design Decisions

### Why Deepest Reporter?

The deepest failure point is usually where the user made their mistake. Earlier failures are often from trying wrong alternatives.

### Why parse_with_debug?

This method automatically formats and prints errors. For programmatic access, use `parse` with rescue.

### Why Line Numbers?

Humans think in lines, not byte positions. Line-oriented output matches how users read their input.

### Why Multiple Test Cases?

Different error scenarios demonstrate the reporter's behavior across grammar constructs.
