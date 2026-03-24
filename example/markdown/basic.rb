# frozen_string_literal: true

# Markdown Parser - Ruby Implementation
#
# Parse a subset of Markdown: headers, paragraphs, lists, code blocks.
#
# Run with: ruby example/markdown/basic.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require "parsanol/parslet"

# Markdown parser
class MarkdownParser < Parsanol::Parser
  root :document

  # Document is a sequence of blocks
  rule(:document) { block.repeat(1).as(:document) }

  # Block-level elements
  rule(:block) do
    code_block |
      heading |
      blockquote |
      unordered_list |
      ordered_list |
      paragraph
  end

  # Heading: # to ######
  rule(:heading) do
    (str("#").repeat(1, 6).as(:level) >>
     space >>
     heading_content.as(:text) >>
     newline).as(:heading)
  end

  rule(:heading_content) do
    (newline.absent? >> any).repeat(1)
  end

  # Paragraph: text until blank line
  rule(:paragraph) do
    (paragraph_line >> newline).repeat(1).as(:paragraph)
  end

  rule(:paragraph_line) do
    (blank_line.absent? >> (str("#").absent? | space.absent?) >> any).repeat(1)
  end

  # Code block: ``` ... ```
  rule(:code_block) do
    (str("```") >>
     (str("`").absent? >> any).repeat.as(:language) >>
     newline >>
     code_content.as(:code) >>
     str("```") >>
     newline?).as(:code_block)
  end

  rule(:code_content) do
    (str("```").absent? >> any).repeat
  end

  # Blockquote: > text
  rule(:blockquote) do
    (str(">") >>
     space? >>
     quote_content.as(:text) >>
     newline).as(:blockquote)
  end

  rule(:quote_content) do
    (newline.absent? >> any).repeat(1)
  end

  # Unordered list: - or * items
  rule(:unordered_list) do
    unordered_item.repeat(1).as(:unordered_list)
  end

  rule(:unordered_item) do
    (match("[*-]") >>
     space >>
     list_content.as(:text) >>
     newline).as(:item)
  end

  # Ordered list: 1. items
  rule(:ordered_list) do
    ordered_item.repeat(1).as(:ordered_list)
  end

  rule(:ordered_item) do
    (match("[0-9]").repeat(1).as(:number) >>
     str(".") >>
     space >>
     list_content.as(:text) >>
     newline).as(:item)
  end

  rule(:list_content) do
    (newline.absent? >> any).repeat(1)
  end

  # Inline elements
  rule(:inline) do
    bold |
      italic |
      code_inline |
      link |
      text
  end

  rule(:bold) do
    (str("**") >>
     (str("**").absent? >> any).repeat(1).as(:text) >>
     str("**")).as(:bold)
  end

  rule(:italic) do
    (str("*") >>
     (str("*").absent? >> any).repeat(1).as(:text) >>
     str("*")).as(:italic)
  end

  rule(:code_inline) do
    (str("`") >>
     (str("`").absent? >> any).repeat(1).as(:code) >>
     str("`")).as(:code)
  end

  rule(:link) do
    (str("[") >>
     (str("]").absent? >> any).repeat(1).as(:text) >>
     str("]") >>
     str("(") >>
     (str(")").absent? >> any).repeat(1).as(:url) >>
     str(")")).as(:link)
  end

  rule(:text) do
    any.repeat(1).as(:text)
  end

  # Helpers
  rule(:space) { str(" ") }
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

  rule(heading: { level: simple(:l), text: simple(:t) }) do
    Heading.new(l.to_s, t.to_s.strip)
  end

  rule(paragraph: sequence(:lines)) do
    Paragraph.new(lines.map(&:to_s))
  end

  rule(code_block: { language: simple(:lang), code: simple(:c) }) do
    CodeBlock.new(lang.to_s.strip, c.to_s)
  end

  rule(blockquote: { text: simple(:t) }) do
    Blockquote.new(t.to_s.strip)
  end

  rule(unordered_list: sequence(:items)) do
    UnorderedList.new(items)
  end

  rule(ordered_list: sequence(:items)) do
    OrderedList.new(items)
  end

  rule(item: { text: simple(:t) }) { { text: t.to_s.strip } }
  rule(item: { number: simple(:n), text: simple(:t) }) do
    { number: n.to_s, text: t.to_s.strip }
  end
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
if __FILE__ == $PROGRAM_NAME
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

  result = parse_markdown("#{markdown}\n")

  if result
    puts "Parsed AST:"
    puts result.inspect
    puts
    puts "HTML Output:"
    puts result.to_html
  end
end
