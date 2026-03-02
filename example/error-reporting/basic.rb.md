# Error Reporting - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/error-reporting
ruby basic.rb
```

## Code Walkthrough

### Common Rules

Whitespace and comments are handled uniformly:

```ruby
rule(:space) { match('[ \t]').repeat(1) }
rule(:space?) { space.maybe }
rule(:newline) { match('[\r\n]') }
rule(:comment) { str('#') >> match('[^\r\n]').repeat }
```

Separating common rules improves readability.

### Line Separator Rule

Complex line ending handles comments:

```ruby
rule(:line_separator) {
  (space? >> ((comment.maybe >> newline) | str(';')) >> space?).repeat(1)
}
```

Lines can end with newline, semicolon, or comment followed by newline.

### Block Structure

Define and begin blocks share body structure:

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

Both have opening keyword, content, and closing `end`.

### Body Rule

Bodies contain expressions or nested blocks:

```ruby
rule(:body) {
  (line_separator >> (block | expression)).repeat(1).as(:body) >>
  line_separator
}
```

Recursive structure allows arbitrary nesting.

### parse_with_debug

The example uses debug parsing:

```ruby
parser.parse_with_debug(d)
```

This method prints detailed error information when parsing fails.

### Prettify Helper

Error context is displayed with line numbers:

```ruby
def prettify(str)
  puts " "*3 + " "*4 + "." + " "*4 + "10" + " "*3 + "." + " "*4 + "20"
  str.lines.each_with_index do |line, index|
    printf "%02d %s\n", index+1, line.chomp
  end
end
```

Column markers help identify error positions.

## Output Types

```ruby
# Successful parse:
{:define=>"define", :name=>"f", :body=>[...]}

# Parse failure with debug:
# Displays:
# - Expected token at position
# - Line and column information
# - What was found vs. expected
```

## Design Decisions

### Why Separate Line Separator?

Line endings in this language can include comments. A dedicated rule handles the complexity.

### Why parse_with_debug?

`parse_with_debug` provides developer-friendly error output, essential for language tooling.

### Why Multiple Test Cases?

The example tests both simple and nested structures to demonstrate error reporting at different nesting levels.
