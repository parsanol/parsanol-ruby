# frozen_string_literal: true

# TOML Parser - Ruby Implementation
#
# Parse TOML configuration files: key-value pairs, tables, arrays.
#
# Run with: ruby example/toml/basic.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol/parslet'

# TOML parser
class TomlParser < Parsanol::Parser
  root :document

  # Document is a sequence of entries
  rule(:document) { (comment | table | key_value | newline).repeat.as(:document) }

  # Comment: # to end of line
  rule(:comment) do
    (str('#') >> (newline.absent? >> any).repeat).as(:comment) >> newline
  end

  # Table: [name] or [name.sub]
  rule(:table) do
    (str('[') >>
     table_name.as(:name) >>
     str(']') >>
     newline).as(:table)
  end

  rule(:table_name) do
    (match('[a-zA-Z0-9_]') | str('.') | str('-')).repeat(1)
  end

  # Key-value pair: key = value
  rule(:key_value) do
    (key.as(:key) >>
     space? >>
     str('=') >>
     space? >>
     value.as(:value) >>
     newline).as(:key_value)
  end

  rule(:key) do
    (match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat).as(:key)
  end

  # Value types
  rule(:value) do
    string |
      integer |
      float |
      boolean |
      array |
      inline_table
  end

  # String: basic "..." or literal '...'
  rule(:string) do
    basic_string | literal_string
  end

  rule(:basic_string) do
    (str('"') >>
     ((str('\\').ignore >> any) | (str('"').absent? >> any)).repeat.as(:string) >>
     str('"')).as(:basic_string)
  end

  rule(:literal_string) do
    (str("'") >>
     (str("'").absent? >> any).repeat.as(:string) >>
     str("'")).as(:literal_string)
  end

  # Integer: +/-digits
  rule(:integer) do
    (str('+') | str('-')).maybe >>
      match('[0-9]').repeat(1).as(:integer)
  end

  # Float: digits.digits or scientific notation
  rule(:float) do
    ((str('+') | str('-')).maybe >>
     match('[0-9]').repeat(1) >>
     str('.') >>
     match('[0-9]').repeat(1) >>
     (match('[eE]') >> (str('+') | str('-')).maybe >> match('[0-9]').repeat(1)).maybe).as(:float)
  end

  # Boolean: true or false
  rule(:boolean) do
    (str('true') | str('false')).as(:boolean)
  end

  # Array: [...]
  rule(:array) do
    str('[') >>
      space? >>
      (value >> (comma >> value).repeat).maybe.as(:elements) >>
      space? >>
      str(']').as(:array)
  end

  # Inline table: {...}
  rule(:inline_table) do
    (str('{') >>
     space? >>
     (key_value_inline >> (comma >> key_value_inline).repeat).maybe.as(:pairs) >>
     space? >>
     str('}')).as(:inline_table)
  end

  rule(:key_value_inline) do
    key.as(:key) >> space? >> str('=') >> space? >> value.as(:value)
  end

  # Helpers
  rule(:space?) { match('\s').repeat }
  rule(:comma) { str(',') >> space? }
  rule(:newline) { match('\n') | match('\r\n') }
end

# TOML result classes
TomlDocument = Struct.new(:entries) do
  def to_h
    result = {}
    current_table = nil

    entries.each do |entry|
      case entry
      when TomlTable
        current_table = entry.name
        result[current_table] ||= {}
      when TomlKeyValue
        if current_table
          result[current_table][entry.key] = entry.value
        else
          result[entry.key] = entry.value
        end
      end
    end

    result
  end
end

TomlTable = Struct.new(:name)
TomlKeyValue = Struct.new(:key, :value)
TomlComment = Struct.new(:text)

# Transform parse tree to AST
class TomlTransform < Parsanol::Transform
  rule(document: sequence(:entries)) { TomlDocument.new(entries) }

  rule(table: { name: simple(:n) }) { TomlTable.new(n.to_s) }

  rule(key_value: { key: simple(:k), value: simple(:v) }) do
    TomlKeyValue.new(k.to_s, v)
  end

  rule(comment: simple(:c)) { TomlComment.new(c.to_s) }

  # Value transformations
  rule(basic_string: simple(:s)) { s.to_s }
  rule(literal_string: simple(:s)) { s.to_s }
  rule(integer: simple(:i)) { i.to_s.to_i }
  rule(float: simple(:f)) { f.to_s.to_f }
  rule(boolean: simple(:b)) { b.to_s == 'true' }
  rule(array: { elements: simple(:e) }) { [e] }
  rule(array: { elements: sequence(:es) }) { es }
  rule(inline_table: { pairs: simple(:p) }) { { p[:key] => p[:value] } }
  rule(inline_table: { pairs: sequence(:ps) }) do
    ps.to_h { |p| [p[:key], p[:value]] }
  end
end

# Parse TOML string
def parse_toml(str)
  parser = TomlParser.new
  transform = TomlTransform.new

  tree = parser.parse(str)
  transform.apply(tree)
rescue Parsanol::ParseError => e
  puts "Parse error: #{e.message}"
  nil
end

# Main demo
if __FILE__ == $PROGRAM_NAME
  puts 'TOML Parser'
  puts '=' * 50
  puts

  toml = <<~TOML
    # This is a comment
    title = "TOML Example"

    [database]
    host = "localhost"
    port = 5432
    enabled = true
    connection_timeout = 30.5

    [server]
    hosts = ["alpha", "beta", "gamma"]
    ports = [8080, 8081, 8082]
  TOML

  puts 'Input:'
  puts '-' * 50
  puts toml
  puts '-' * 50
  puts

  result = parse_toml(toml)

  if result
    puts 'Parsed AST:'
    pp result
    puts
    puts 'Hash Output:'
    pp result.to_h
  end
end
