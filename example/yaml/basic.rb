# frozen_string_literal: true

# YAML Parser - Ruby Implementation
#
# Parse a subset of YAML: key-value pairs, lists, nested maps, scalars.
#
# Run with: ruby example/yaml/basic.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol/parslet'

# YAML parser (subset)
class YamlParser < Parsanol::Parser
  root :document

  # Document is a sequence of mappings or list items
  rule(:document) { (mapping | list_item | comment | blank_line).repeat(1).as(:document) }

  # Comment: # to end of line
  rule(:comment) do
    (space? >> str('#') >> (newline.absent? >> any).repeat).as(:comment) >> newline
  end

  # Blank line
  rule(:blank_line) { space? >> newline }

  # Mapping (key-value)
  rule(:mapping) do
    (key.as(:key) >>
     colon >>
     (inline_value | indented_value)).as(:mapping)
  end

  rule(:key) do
    (match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat).as(:key)
  end

  rule(:colon) { str(':') >> space }

  # Inline value: on same line as key
  rule(:inline_value) do
    space? >> (string | integer | float | boolean | null).as(:value) >> newline
  end

  # Indented value: nested block
  rule(:indented_value) do
    newline >> indented_block.as(:block)
  end

  rule(:indented_block) do
    (indent >> (mapping | list_item) >> (newline >> indent >> (mapping | list_item)).repeat).as(:block)
  end

  # List item: - value
  rule(:list_item) do
    (str('-') >> space >>
     (inline_list_value | indented_value)).as(:list_item)
  end

  rule(:inline_list_value) do
    space? >> (string | integer | float | boolean | null).as(:value) >> newline
  end

  # Scalar types
  rule(:string) do
    quoted_string | plain_string
  end

  rule(:quoted_string) do
    (str('"') >>
     ((str('\\').ignore >> any) | (str('"').absent? >> any)).repeat.as(:string) >>
     str('"')) |
      (str("'") >>
       (str("'").absent? >> any).repeat.as(:string) >>
       str("'"))
  end

  rule(:plain_string) do
    (newline.absent? >> str(':').absent? >> any).repeat(1).as(:string)
  end

  rule(:integer) do
    (str('+') | str('-')).maybe >>
      match('[0-9]').repeat(1)
  end

  rule(:float) do
    (str('+') | str('-')).maybe >>
      match('[0-9]').repeat(1) >>
      str('.') >>
      match('[0-9]').repeat(1)
  end

  rule(:boolean) do
    str('true') | str('false')
  end

  rule(:null) do
    str('null') | str('~')
  end

  # Helpers
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { match('\s').repeat }
  rule(:newline) { match('\n') | match('\r\n') }
  rule(:indent) { str('  ') | str("\t") }
end

# YAML result classes
YamlDocument = Struct.new(:entries) do
  def to_h
    result = {}
    entries.each do |entry|
      case entry
      when YamlMapping
        result[entry.key] = entry.value
      end
    end
    result
  end
end

YamlMapping = Struct.new(:key, :value)
YamlListItem = Struct.new(:value)
YamlComment = Struct.new(:text)

# Transform parse tree to AST
class YamlTransform < Parsanol::Transform
  rule(document: sequence(:entries)) { YamlDocument.new(entries) }

  rule(mapping: { key: simple(:k), value: simple(:v) }) do
    YamlMapping.new(k.to_s, v)
  end

  rule(mapping: { key: simple(:k), block: simple(:b) }) do
    YamlMapping.new(k.to_s, b)
  end

  rule(list_item: { value: simple(:v) }) do
    YamlListItem.new(v)
  end

  rule(list_item: { block: simple(:b) }) do
    YamlListItem.new(b)
  end

  rule(comment: simple(:c)) { YamlComment.new(c.to_s) }

  # Value transformations
  rule(string: simple(:s)) { s.to_s.strip }
  rule(integer: simple(:i)) { i.to_s.to_i }
  rule(float: simple(:f)) { f.to_s.to_f }
  rule(value: simple(:v)) { v }
  rule(block: simple(:b)) { b }
  rule(block: sequence(:bs)) do
    result = {}
    bs.each do |b|
      result[b.key] = b.value if b.is_a?(YamlMapping)
    end
    result
  end
end

# Parse YAML string
def parse_yaml(str)
  parser = YamlParser.new
  transform = YamlTransform.new

  tree = parser.parse(str)
  transform.apply(tree)
rescue Parsanol::ParseError => e
  puts "Parse error: #{e.message}"
  nil
end

# Main demo
if __FILE__ == $PROGRAM_NAME
  puts 'YAML Parser'
  puts '=' * 50
  puts

  yaml = <<~YAML
    # Configuration file
    name: Example Application
    version: 1.0.0
    debug: true
    timeout: 30.5

    database:
      host: localhost
      port: 5432
      name: myapp

    servers:
      - alpha
      - beta
      - gamma
  YAML

  puts 'Input:'
  puts '-' * 50
  puts yaml
  puts '-' * 50
  puts

  result = parse_yaml(yaml)

  if result
    puts 'Parsed AST:'
    pp result
    puts
    puts 'Hash Output:'
    pp result.to_h
  end
end
