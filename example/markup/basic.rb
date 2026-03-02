# frozen_string_literal: true

# Markup Parser - Ruby Implementation
#
# Parse a simple markup language: headers, lists, paragraphs, inline formatting.
#
# Run with: ruby example/markup/basic.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol/parslet'

# Simple markup parser
class MarkupParser < Parsanol::Parser
  root :document

  # Document is a sequence of blocks
  rule(:document) { block.repeat(1).as(:document) }

  # Block-level elements
  rule(:block) do
    heading |
      unordered_list |
      paragraph |
      blank_line.as(:blank)
  end

  # Heading: = for H1, == for H2, === for H3
  rule(:heading) do
    (str('=').repeat(1, 3).as(:level) >>
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
    (blank_line.absent? >> (str('=').absent? | space.absent?) >> any).repeat(1)
  end

  # Unordered list: - items
  rule(:unordered_list) do
    list_item.repeat(1).as(:unordered_list)
  end

  rule(:list_item) do
    (str('-') >>
     space >>
     list_content.as(:text) >>
     newline).as(:item)
  end

  rule(:list_content) do
    (newline.absent? >> any).repeat(1)
  end

  # Helpers
  rule(:space) { str(' ') }
  rule(:newline) { match('\n') }
  rule(:blank_line) { match('\s').repeat >> newline }
end

# Markup node classes
MarkupDocument = Struct.new(:children) do
  def to_html
    children.map { |c| c.respond_to?(:to_html) ? c.to_html : '' }.join("\n")
  end
end

MarkupHeading = Struct.new(:level, :text) do
  def to_html
    h = level.length
    "<h#{h}>#{text.strip}</h#{h}>"
  end
end

MarkupParagraph = Struct.new(:lines) do
  def to_html
    content = lines.map(&:strip).join(' ')
    "<p>#{content}</p>" unless content.empty?
  end
end

MarkupList = Struct.new(:items) do
  def to_html
    html = items.map { |i| "<li>#{i[:text].strip}</li>" }.join("\n")
    "<ul>\n#{html}\n</ul>"
  end
end

# Transform parse tree to AST
class MarkupTransform < Parsanol::Transform
  rule(document: sequence(:blocks)) do
    MarkupDocument.new(blocks.reject { |b| b == :blank })
  end

  rule(heading: { level: simple(:l), text: simple(:t) }) do
    MarkupHeading.new(l.to_s, t.to_s)
  end

  rule(paragraph: sequence(:lines)) do
    MarkupParagraph.new(lines.map(&:to_s))
  end

  rule(unordered_list: sequence(:items)) do
    MarkupList.new(items)
  end

  rule(item: { text: simple(:t) }) { { text: t.to_s } }
  rule(blank: simple(:_)) { :blank }
end

# Parse markup string
def parse_markup(str)
  parser = MarkupParser.new
  transform = MarkupTransform.new

  tree = parser.parse(str)
  transform.apply(tree)
rescue Parsanol::ParseError => e
  puts "Parse error: #{e.message}"
  nil
end

# Main demo
if __FILE__ == $PROGRAM_NAME
  puts 'Markup Parser'
  puts '=' * 50
  puts

  markup = <<~MU
    = Main Title

    This is a paragraph of text.
    It can span multiple lines.

    = Section One

    - First item
    - Second item
    - Third item

    == Subsection

    Another paragraph here.

    === Detail

    Final content.
  MU

  puts 'Input:'
  puts '-' * 50
  puts markup
  puts '-' * 50
  puts

  result = parse_markup("#{markup}\n")

  if result
    puts 'Parsed AST:'
    pp result
    puts
    puts 'HTML Output:'
    puts result.to_html
  end
end
