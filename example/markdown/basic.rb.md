# Markdown Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/markdown
ruby basic.rb
```

## Code Walkthrough

### Document Structure

A document is a sequence of block-level elements:

```ruby
rule(:document) { block.repeat(1).as(:document) }

rule(:block) {
  code_block |
  heading |
  blockquote |
  unordered_list |
  ordered_list |
  paragraph
}
```

Order matters: more specific patterns (code_block) before general (paragraph).

### Heading Rule

One to six hash symbols define heading level:

```ruby
rule(:heading) {
  (str('#').repeat(1, 6).as(:level) >>
   space >>
   heading_content.as(:text) >>
   newline).as(:heading)
}
```

The captured `level` string length determines `h1` through `h6`.

### Paragraph Rule

Consecutive non-blank lines form a paragraph:

```ruby
rule(:paragraph) {
  (paragraph_line >> newline).repeat(1).as(:paragraph)
}

rule(:paragraph_line) {
  (blank_line.absent? >> any).repeat(1)
}
```

Blank lines separate paragraphs.

### Code Block Rule

Fenced code with optional language:

```ruby
rule(:code_block) {
  (str('```') >>
   (str('`').absent? >> any).repeat.as(:language) >>
   newline >>
   code_content.as(:code) >>
   str('```') >>
   newline?).as(:code_block)
}
```

Language identifier appears on the first line after backticks.

### Blockquote Rule

Lines prefixed with `>`:

```ruby
rule(:blockquote) {
  (str('>') >>
   space? >>
   quote_content.as(:text) >>
   newline).as(:blockquote)
}
```

Optional space after `>` is consumed.

### Unordered List Rule

Items start with `-` or `*`:

```ruby
rule(:unordered_list) {
  unordered_item.repeat(1).as(:unordered_list)
}

rule(:unordered_item) {
  (match('[*-]') >>
   space >>
   list_content.as(:text) >>
   newline).as(:item)
}
```

Each item must be on its own line.

### Ordered List Rule

Items start with number and period:

```ruby
rule(:ordered_item) {
  (match('[0-9]').repeat(1).as(:number) >>
   str('.') >>
   space >>
   list_content.as(:text) >>
   newline).as(:item)
}
```

Number is captured for potential renumbering.

## Output Types

```ruby
# Document with multiple blocks
Document.new([Heading.new("##", "Title"), Paragraph.new(["text"])])

# Heading with level and text
Heading.new("###", "Section Title")
# to_html => "<h3>Section Title</h3>"

# Code block with language
CodeBlock.new("ruby", "def hello\n  puts 'hi'\nend")
# to_html => "<pre><code class=\"ruby\">...</code></pre>"
```

## Design Decisions

### Why Block Order Matters?

Paragraph is a fallback that matches almost anything. Specific patterns must be tried first.

### Why Fenced Code Blocks?

Fenced blocks (```) are easier to parse than indented code. They also support language tags.

### Why Separate List Types?

Unordered and ordered lists have different markers and semantics. Separate rules allow different processing.

### Why Struct for AST Nodes?

Structs are lightweight and can define `to_html` for clean HTML generation without external dependencies.
