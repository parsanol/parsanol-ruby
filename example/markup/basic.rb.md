# Markup Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/markup
ruby basic.rb
```

## Code Walkthrough

### Document Structure

A document is a sequence of blocks:

```ruby
rule(:document) { block.repeat(1).as(:document) }

rule(:block) {
  heading |
  unordered_list |
  paragraph |
  blank_line.as(:blank)
}
```

Blank lines are captured separately and filtered during transformation.

### Heading Rule

Equal signs define heading level (1-3):

```ruby
rule(:heading) {
  (str('=').repeat(1, 3).as(:level) >>
   space >>
   heading_content.as(:text) >>
   newline).as(:heading)
}
```

`=` is H1, `==` is H2, `===` is H3.

### Paragraph Rule

Consecutive lines form paragraphs:

```ruby
rule(:paragraph) {
  (paragraph_line >> newline).repeat(1).as(:paragraph)
}

rule(:paragraph_line) {
  (blank_line.absent? >> (str('=').absent? | space.absent?) >> any).repeat(1)
}
```

Paragraph lines don't start with `=` followed by space (which would be a heading).

### List Rule

Hyphen-prefixed items:

```ruby
rule(:unordered_list) {
  list_item.repeat(1).as(:unordered_list)
}

rule(:list_item) {
  (str('-') >>
   space >>
   list_content.as(:text) >>
   newline).as(:item)
}
```

Each item must be on its own line with hyphen and space.

## Output Types

```ruby
# Document with blocks
MarkupDocument.new([
  MarkupHeading.new("=", "Title"),
  MarkupParagraph.new(["text"]),
  MarkupList.new([{text: "item"}, {text: "item2"}])
])

# Heading
MarkupHeading.new("==", "Section")
# to_html => "<h2>Section</h2>"

# Paragraph
MarkupParagraph.new(["Line one", "Line two"])
# to_html => "<p>Line one Line two</p>"

# List
MarkupList.new([{text: "First"}, {text: "Second"}])
# to_html => "<ul>\n<li>First</li>\n<li>Second</li>\n</ul>"
```

## Design Decisions

### Why Equal Signs for Headings?

Equal signs are visually intuitive and don't conflict with common text. They're also easier to type than `#` on some keyboards.

### Why Filter Blank Lines in Transform?

Blank lines separate blocks but aren't content. Filtering them during transformation keeps the AST clean.

### Why Separate Paragraph Lines?

Keeping lines separate allows joining with spaces during HTML generation, preserving word boundaries across line breaks.

### Why Limit Heading Levels to 3?

This markup language is intentionally simple. Real-world use might extend to 6 levels, matching HTML.
