# frozen_string_literal: true

# JSON Parser Example - Ruby Transform: Ruby Transform (Parslet-Compatible)
#
# This example demonstrates Ruby Transform for parsing JSON:
# 1. Rust parser (parsanol-rs) does the fast parsing
# 2. Returns a generic tree (hash/array/string structure)
# 3. Ruby transform converts tree to Ruby objects
#
# This is the most flexible option and is 100% Parslet API compatible.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol'

# Step 1: Define the JSON parser grammar
class JsonParser < Parsanol::Parser
  root :json

  rule(:json) { space? >> value >> space? }

  rule(:value) do
    object |
      array |
      string |
      number |
      true_value |
      false_value |
      null_value
  end

  # Object: { "key": value, ... }
  rule(:object) do
    str('{') >> space? >>
      (entry >> (comma >> entry).repeat).maybe.as(:object) >>
      space? >> str('}')
  end

  rule(:entry) do
    (string.as(:key) >> space? >> colon >> space? >> value.as(:val)).as(:entry)
  end

  # Array: [ value, ... ]
  rule(:array) do
    str('[') >> space? >>
      (value >> (comma >> value).repeat).maybe.as(:array) >>
      space? >> str(']')
  end

  # String: "..."
  rule(:string) do
    str('"') >> (
      (str('\\') >> any) | (str('"').absent? >> any)
    ).repeat.as(:string) >> str('"')
  end

  # Number: -?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?
  rule(:number) do
    (
      str('-').maybe >>
      (str('0') | (match('[1-9]') >> digit.repeat)) >>
      (str('.') >> digit.repeat(1)).maybe >>
      (match('[eE]') >> (str('+') | str('-')).maybe >> digit.repeat(1)).maybe
    ).as(:number)
  end

  # Literals
  rule(:true_value) { str('true').as(true) }
  rule(:false_value) { str('false').as(false) }
  rule(:null_value) { str('null').as(:null) }

  # Helpers
  rule(:digit) { match('[0-9]') }
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }
  rule(:comma) { space? >> str(',') >> space? }
  rule(:colon) { str(':') }
end

# Step 2: Define the transform (Parslet-style)
class JsonTransform < Parsanol::Transform
  # Entry helper class
  Entry = Struct.new(:key, :val)

  # Transform arrays
  rule(array: subtree(:ar)) do
    ar.is_a?(Array) ? ar : [ar]
  end

  # Transform objects
  rule(object: subtree(:ob)) do
    (ob.is_a?(Array) ? ob : [ob]).to_h { |e| [e.key, e.val] }
  end

  # Transform entries
  rule(entry: { key: simple(:ke), val: simple(:va) }) do
    Entry.new(ke, va)
  end

  # Transform strings
  rule(string: simple(:st)) do
    st.to_s
  end

  # Transform numbers
  rule(number: simple(:nb)) do
    str = nb.to_s
    str.match?(/[eE.]/) ? Float(str) : Integer(str)
  end

  # Transform literals
  rule(null: simple(:_nu)) { nil }
  rule(true => simple(:_tr)) { true }
  rule(false => simple(:_fa)) { false }
end

# Step 3: Parse and transform
def parse_json(input)
  parser = JsonParser.new
  transform = JsonTransform.new

  # Ruby Transform: Parse in Rust, transform in Ruby
  tree = parser.parse(input)
  puts "Parse tree (first 500 chars): #{tree.inspect[0..500]}..."

  result = transform.apply(tree)
  puts "Result: #{result.inspect[0..200]}..."

  result
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  puts '=' * 60
  puts 'JSON Parser Example - Ruby Transform: Ruby Transform'
  puts '=' * 60

  test_cases = [
    ['"hello"', 'hello'],
    ['42', 42],
    ['3.14', 3.14],
    ['true', true],
    ['false', false],
    ['null', nil],
    ['[1, 2, 3]', [1, 2, 3]],
    ['{"a": 1}', { 'a' => 1 }],
    ['{"name": "test", "value": 42}', { 'name' => 'test', 'value' => 42 }]
  ]

  test_cases.each do |input, expected|
    puts
    puts '-' * 40
    puts "Input: #{input}"
    begin
      result = parse_json(input)
      status = result == expected ? '✓ PASS' : '✗ FAIL'
      puts "Expected: #{expected.inspect}, Got: #{result.inspect} - #{status}"
    rescue StandardError => e
      puts "Error: #{e.message}"
      puts e.backtrace.first(3).join("\n")
      puts '✗ FAIL'
    end
  end

  # Complex example
  puts
  puts '-' * 40
  puts 'Complex JSON example:'
  complex_json = <<~JSON
    {
      "users": [
        {"name": "Alice", "age": 30, "active": true},
        {"name": "Bob", "age": 25, "active": false}
      ],
      "count": 2,
      "metadata": {
        "version": "1.0",
        "tags": ["admin", "test"]
      }
    }
  JSON

  begin
    result = parse_json(complex_json)
    puts 'Parsed successfully!'
    puts "Users: #{result['users'].map { |u| u['name'] }.join(', ')}"
    puts "Count: #{result['count']}"
    puts "Version: #{result['metadata']['version']}"
    puts '✓ PASS'
  rescue StandardError => e
    puts "Error: #{e.message}"
    puts '✗ FAIL'
  end

  puts
  puts '=' * 60
  puts 'Ruby Transform Benefits for JSON:'
  puts '- Flexible: Can add custom transform logic'
  puts '- Debuggable: Inspect tree before transform'
  puts '- Compatible: Works with existing Parslet code'
  puts '=' * 60
end
