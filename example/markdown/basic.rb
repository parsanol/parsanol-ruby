# Markdown Parser - Ruby Implementation
#
# Parse a subset of Markdown: headers, paragraphs, lists, code blocks.
#
# Run with: ruby example/markdown/basic.rb

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol/parslet'

# Markdown parser
class MarkdownParser < Parsanol::Parser
  root :document

  # Document is a sequence of blocks
  rule(:document) { block.repeat(1).as(:document) }

  # Block-level elements
  rule(:block) {
    code_block |
    heading |
    blockquote |
    unordered_list |
    ordered_list |
    paragraph
  }

  # Heading: # to ######
  rule(:heading) {
    (str('#').repeat(1, 6).as(:level) >>
     space >>
     heading_content.as(:text) >>
     newline).as(:heading)
  }

  rule(:heading_content) {
    (newline.absent? >> any).repeat(1)
  }

  # Paragraph: text until blank line
  rule(:paragraph) {
    (paragraph_line >> newline).repeat(1).as(:paragraph)
  }

  rule(:paragraph_line) {
    (blank_line.absent? >> (str('#').absent? | space.absent?) >> any).repeat(1)
  }

  # Code block: ``` ... ```
  rule(:code_block) {
    (str('```') >>
     (str('`').absent? >> any).repeat.as(:language) >>
     newline >>
     code_content.as(:code) >>
     str('```') >>
     newline?).as(:code_block)
  }

  rule(:code_content) {
    (str('```').absent? >> any).repeat
  }

  # Blockquote: > text
  rule(:blockquote) {
    (str('>') >>
     space? >>
     quote_content.as(:text) >>
     newline).as(:blockquote)
  }

  rule(:quote_content) {
    (newline.absent? >> any).repeat(1)
  }

  # Unordered list: - or * items
  rule(:unordered_list) {
    unordered_item.repeat(1).as(:unordered_list)
  }

  rule(:unordered_item) {
    (match('[*-]') >>
     space >>
     list_content.as(:text) >>
     newline).as(:item)
  }

  # Ordered list: 1. items
  rule(:ordered_list) {
    ordered_item.repeat(1).as(:ordered_list)
  }

  rule(:ordered_item) {
    (match('[0-9]').repeat(1).as(:number) >>
     str('.') >>
     space >>
     list_content.as(:text) >>
     newline).as(:item)
  }

  rule(:list_content) {
    (newline.absent? >> any).repeat(1)
  }

  # Inline elements
  rule(:inline) {
    bold |
    italic |
    code_inline |
    link |
    text
  }

  rule(:bold) {
    (str('**') >>
     (str('**').absent? >> any).repeat(1).as(:text) >>
     str('**')).as(:bold)
  }

  rule(:italic) {
    (str('*') >>
     (str('*').absent? >> any).repeat(1).as(:text) >>
     str('*')).as(:italic)
  }

  rule(:code_inline) {
    (str('`') >>
     (str('`').absent? >> any).repeat(1).as(:code) >>
     str('`')).as(:code)
  }

  rule(:link) {
    (str('[') >>
     (str(']').absent? >> any).repeat(1).as(:text) >>
     str(']') >>
     str('(') >>
     (str(')').absent? >> any).repeat(1).as(:url) >>
     str(')')).as(:link)
  }

  rule(:text) {
    any.repeat(1).as(:text)
  }

  # Helpers
  rule(:space) { str(' ') }
  rule(:space?) { match('\s').repeat }
  rule(:newline) { match('\n') }
  rule(:newline?) { match('\n').maybe }
  rule(:blank_line) { match('\s').repeat >> newline }
end

# Markdown node classes
Document = Struct.new(:children) do
  def to_html
    children.map { |c| c.respond_to?(:to_html) ? c.to_html : c.to_s }.join("\n")
  end
end

Heading = Struct.new(:level, :text) do
  def to_html
    h = level.length
    "<h#{h}>#{text}</h#{h}>"
  end
end

Paragraph = Struct.new(:lines) do
  def to_html
    "<p>#{lines.map(&:strip).join(' ')}</p>"
  end
end

CodeBlock = Struct.new(:language, :code) do
  def to_html
    "<pre><code class=\"#{language}\">#{code}</code></pre>"
  end
end

Blockquote = Struct.new(:text) do
  def to_html
    "<blockquote>#{text}</blockquote>"
  end
end

UnorderedList = Struct.new(:items) do
  def to_html
    html = items.map { |i| "<li>#{i[:text]}</li>" }.join("\n")
    "<ul>\n#{html}\n</ul>"
  end
end

OrderedList = Struct.new(:items) do
  def to_html
    html = items.map { |i| "<li>#{i[:text]}</li>" }.join("\n")
    "<ol>\n#{html}\n</ol>"
  end
end

# Transform parse tree to AST
class MarkdownTransform < Parsanol::Transform
  rule(document: sequence(:blocks)) { Document.new(blocks) }

  rule(heading: { level: simple(:l), text: simple(:t) }) {
    Heading.new(l.to_s, t.to_s.strip)
  }

  rule(paragraph: sequence(:lines)) {
    Paragraph.new(lines.map(&:to_s))
  }

  rule(code_block: { language: simple(:lang), code: simple(:c) }) {
    CodeBlock.new(lang.to_s.strip, c.to_s)
  }

  rule(blockquote: { text: simple(:t) }) {
    Blockquote.new(t.to_s.strip)
  }

  rule(unordered_list: sequence(:items)) {
    UnorderedList.new(items)
  }

  rule(ordered_list: sequence(:items)) {
    OrderedList.new(items)
  }

  rule(item: { text: simple(:t) }) { { text: t.to_s.strip } }
  rule(item: { number: simple(:n), text: simple(:t) }) { { number: n.to_s, text: t.to_s.strip } }
end

# Parse markdown string
def parse_markdown(str)
  parser = MarkdownParser.new
  transform = MarkdownTransform.new

  tree = parser.parse(str)
  transform.apply(tree)
rescue Parsanol::ParseError => e
  puts "Parse error: #{e.message}"
  nil
end

# Main demo
if __FILE__ == $0
  puts "Markdown Parser"
  puts "=" * 50
  puts

  markdown = <<~MD
    # Main Title

    This is a paragraph with **bold** and *italic* text.

    ## Second Heading

    > This is a blockquote

    - Item one
    - Item two
    - Item three

    1. First
    2. Second
    3. Third

    ```ruby
    def hello
      puts "Hello, World!"
    end
    ```
  MD

  puts "Input:"
  puts "-" * 50
  puts markdown
  puts "-" * 50
  puts

  result = parse_markdown(markdown + "\n")

  if result
    puts "Parsed AST:"
    puts result.inspect
    puts
    puts "HTML Output:"
    puts result.to_html
  end
end
