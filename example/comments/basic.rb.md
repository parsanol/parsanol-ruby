# Comments Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/comments
ruby basic.rb
```

## Code Walkthrough

### Line Comment Rule

Single-line comments start with `//`:

```ruby
rule(:line_comment) {
  (str('//') >> (newline.absent? >> any).repeat).as(:line)
}
```

Content extends to end of line; newline is not consumed.

### Multiline Comment Rule

Block comments use `/* */` delimiters:

```ruby
rule(:multiline_comment) {
  (str('/*') >> (str('*/').absent? >> any).repeat >> str('*/')).as(:multi)
}
```

Negative lookahead prevents early termination.

### Space Rule with Comments

Comments are treated as whitespace:

```ruby
rule(:spaces) { space.repeat }
rule(:space) { multiline_comment | line_comment | str(' ') }
```

This allows comments anywhere whitespace is permitted.

### Expression Rule

Simple expressions demonstrate comment handling:

```ruby
rule(:expression) { (str('a').as(:a) >> spaces).as(:exp) }
```

The `spaces` rule consumes any trailing comments.

### Lines and Line Endings

Input is structured as lines:

```ruby
rule(:lines) { line.repeat }
rule(:line) { spaces >> expression.repeat >> newline }
rule(:newline) { str("\n") >> str("\r").maybe }
```

Each line ends with a newline (CRLF or LF).

### parse_with_debug

Debug output shows the complete parse tree:

```ruby
pp ALanguage.new.parse_with_debug(code)
```

Useful for understanding how comments integrate with the grammar.

## Output Types

```ruby
# Parse tree for:
#   a // comment
#   a a a /* inline */ a
#
[
  {:exp=>[{:a=>"a"}]},
  {:exp=>[{:a=>"a"}, {:a=>"a"}, {:a=>"a"}, {:a=>"a"}]}
]
```

Comments are consumed by the `spaces` rule and don't appear in output.

## Design Decisions

### Why Treat Comments as Whitespace?

Comments should be allowed anywhere whitespace is. Making them part of the `space` rule achieves this elegantly.

### Why Not Include Newline in Line Comments?

Newlines are handled separately by the line structure. This keeps comment content clean.

### Why Use Negative Lookahead for Multiline Comments?

`str('*/').absent?` ensures we don't prematurely match the closing delimiter. This is cleaner than trying to enumerate valid characters.

### Why parse_with_debug?

When building grammars, seeing the full parse tree helps debug unexpected matches or failures.
