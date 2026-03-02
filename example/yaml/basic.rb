# YAML Parser - Ruby Implementation
#
# Parse a subset of YAML: key-value pairs, lists, nested maps, scalars.
#
# Run with: ruby example/yaml/basic.rb

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol/parslet'

# YAML parser (subset)
class YamlParser < Parsanol::Parser
  root :document

  # Document is a sequence of mappings or list items
  rule(:document) { (mapping | list_item | comment | blank_line).repeat(1).as(:document) }

  # Comment: # to end of line
  rule(:comment) {
    (space? >> str('#') >> (newline.absent? >> any).repeat).as(:comment) >> newline
  }

  # Blank line
  rule(:blank_line) { space? >> newline }

  # Mapping (key-value)
  rule(:mapping) {
    (key.as(:key) >>
     colon >>
     (inline_value | indented_value)).as(:mapping)
  }

  rule(:key) {
    (match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat).as(:key)
  }

  rule(:colon) { str(':') >> space }

  # Inline value: on same line as key
  rule(:inline_value) {
    (space? >> (string | integer | float | boolean | null).as(:value) >> newline)
  }

  # Indented value: nested block
  rule(:indented_value) {
    (newline >> indented_block.as(:block))
  }

  rule(:indented_block) {
    (indent >> (mapping | list_item) >> (newline >> indent >> (mapping | list_item)).repeat).as(:block)
  }

  # List item: - value
  rule(:list_item) {
    (str('-') >> space >>
     (inline_list_value | indented_value)).as(:list_item)
  }

  rule(:inline_list_value) {
    (space? >> (string | integer | float | boolean | null).as(:value) >> newline)
  }

  # Scalar types
  rule(:string) {
    quoted_string | plain_string
  }

  rule(:quoted_string) {
    (str('"') >>
     (str('\\').ignore >> any | str('"').absent? >> any).repeat.as(:string) >>
     str('"')) |
    (str("'") >>
     (str("'").absent? >> any).repeat.as(:string) >>
     str("'"))
  }

  rule(:plain_string) {
    (newline.absent? >> str(':').absent? >> any).repeat(1).as(:string)
  }

  rule(:integer) {
    (str('+') | str('-')).maybe >>
    match('[0-9]').repeat(1)
  }

  rule(:float) {
    ((str('+') | str('-')).maybe >>
     match('[0-9]').repeat(1) >>
     str('.') >>
     match('[0-9]').repeat(1))
  }

  rule(:boolean) {
    str('true') | str('false')
  }

  rule(:null) {
    str('null') | str('~')
  }

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

  rule(mapping: { key: simple(:k), value: simple(:v) }) {
    YamlMapping.new(k.to_s, v)
  }

  rule(mapping: { key: simple(:k), block: simple(:b) }) {
    YamlMapping.new(k.to_s, b)
  }

  rule(list_item: { value: simple(:v) }) {
    YamlListItem.new(v)
  }

  rule(list_item: { block: simple(:b) }) {
    YamlListItem.new(b)
  }

  rule(comment: simple(:c)) { YamlComment.new(c.to_s) }

  # Value transformations
  rule(string: simple(:s)) { s.to_s.strip }
  rule(integer: simple(:i)) { i.to_s.to_i }
  rule(float: simple(:f)) { f.to_s.to_f }
  rule(value: simple(:v)) { v }
  rule(block: simple(:b)) { b }
  rule(block: sequence(:bs)) {
    result = {}
    bs.each do |b|
      if b.is_a?(YamlMapping)
        result[b.key] = b.value
      end
    end
    result
  }
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
if __FILE__ == $0
  puts "YAML Parser"
  puts "=" * 50
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

  puts "Input:"
  puts "-" * 50
  puts yaml
  puts "-" * 50
  puts

  result = parse_yaml(yaml)

  if result
    puts "Parsed AST:"
    pp result
    puts
    puts "Hash Output:"
    pp result.to_h
  end
end
