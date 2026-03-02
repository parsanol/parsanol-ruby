# JSON Parser Example - Serialized: JSON Serialization
#
# This example demonstrates Serialized for parsing JSON:
# 1. Rust parser (parsanol-rs) does the parsing
# 2. Rust transform converts to typed structs
# 3. Result is serialized to JSON (meta!)
# 4. Ruby deserializes JSON to Ruby objects
#
# Note: Since JSON output is already JSON, Serialized essentially
# validates and normalizes the input JSON.

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol'
require 'json'

# NOTE: This example requires the native extension to support parse_to_json
# which is planned but not yet implemented. This serves as an API preview.

# Step 1: Define the JSON parser grammar (same as Option A)
class JsonParser < Parsanol::Parser
  root :json

  rule(:json) { space? >> value >> space? }

  rule(:value) {
    object |
    array |
    string |
    number |
    true_value |
    false_value |
    null_value
  }

  rule(:object) {
    str('{') >> space? >>
    (entry >> (comma >> entry).repeat).maybe.as(:object) >>
    space? >> str('}')
  }

  rule(:entry) {
    (string.as(:key) >> space? >> colon >> space? >> value.as(:val)).as(:entry)
  }

  rule(:array) {
    str('[') >> space? >>
    (value >> (comma >> value).repeat).maybe.as(:array) >>
    space? >> str(']')
  }

  rule(:string) {
    str('"') >> (
      str('\\') >> any | str('"').absent? >> any
    ).repeat.as(:string) >> str('"')
  }

  rule(:number) {
    (
      str('-').maybe >>
      (str('0') | (match('[1-9]') >> digit.repeat)) >>
      (str('.') >> digit.repeat(1)).maybe >>
      (match('[eE]') >> (str('+') | str('-')).maybe >> digit.repeat(1)).maybe
    ).as(:number)
  }

  rule(:true_value) { str('true').as(:true) }
  rule(:false_value) { str('false').as(:false) }
  rule(:null_value) { str('null').as(:null) }

  rule(:digit) { match('[0-9]') }
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }
  rule(:comma) { space? >> str(',') >> space? }
  rule(:colon) { str(':') }
end

# Step 2: Define Ruby classes for typed output (optional, for structured access)
class JsonValue; end

class JsonString < JsonValue
  attr_reader :value
  def initialize(value:) @value = value end
  def to_ruby = @value
end

class JsonNumber < JsonValue
  attr_reader :value
  def initialize(value:) @value = value end
  def to_ruby = @value
end

class JsonBool < JsonValue
  attr_reader :value
  def initialize(value:) @value = value end
  def to_ruby = @value
end

class JsonNull < JsonValue
  def to_ruby = nil
end

class JsonArray < JsonValue
  attr_reader :elements
  def initialize(elements:) @elements = elements end
  def to_ruby = @elements.map(&:to_ruby)
end

class JsonObject < JsonValue
  attr_reader :members
  def initialize(members:) @members = members end
  def to_ruby = @members.transform_values(&:to_ruby)
end

# Step 3: Deserializer
class JsonValueDeserializer
  def self.from_json(json_string)
    data = JSON.parse(json_string)
    from_ruby(data)
  end

  def self.from_ruby(data)
    case data
    when String
      JsonString.new(value: data)
    when Integer
      JsonNumber.new(value: data)
    when Float
      JsonNumber.new(value: data)
    when true
      JsonBool.new(value: true)
    when false
      JsonBool.new(value: false)
    when nil
      JsonNull.new
    when Array
      JsonArray.new(elements: data.map { |e| from_ruby(e) })
    when Hash
      JsonObject.new(members: data.transform_values { |v| from_ruby(v) })
    else
      raise "Unknown type: #{data.class}"
    end
  end
end

# Step 4: Parse with JSON output
def parse_json(input)
  parser = JsonParser.new

  # Serialized: Parse and get JSON from Rust
  # NOTE: This requires native extension support
  # output_json = parser.parse_to_json(input)

  # For now, simulate by using Option A then serializing
  # Real implementation would call:
  #   Native.parse_to_json(grammar_json, input)

  # Use the parser defined in this file
  tree = parser.parse(input)
  transform = JsonTransform.new
  result = transform.apply(tree)

  # This would come from Rust in Serialized
  output_json = result.to_json
  puts "Output JSON: #{output_json[0..100]}..."

  # Deserialize to typed objects
  typed = JsonValueDeserializer.from_json(output_json)
  puts "Typed: #{typed.class}"

  # Convert to Ruby native types
  typed.to_ruby
end

# Transform class (needed for simulation)
class JsonTransform < Parsanol::Transform
  class Entry < Struct.new(:key, :val); end
  rule(array: subtree(:ar)) { ar.is_a?(Array) ? ar : [ar] }
  rule(object: subtree(:ob)) { (ob.is_a?(Array) ? ob : [ob]).each_with_object({}) { |e, h| h[e.key] = e.val } }
  rule(entry: { key: simple(:ke), val: simple(:va) }) { Entry.new(ke, va) }
  rule(string: simple(:st)) { st.to_s }
  rule(number: simple(:nb)) {
    s = nb.to_s
    s.match?(/[eE.]/) ? Float(s) : Integer(s)
  }
  rule(null: simple(:_nu)) { nil }
  rule(true: simple(:_tr)) { true }
  rule(false: simple(:_fa)) { false }
end

# Example usage
if __FILE__ == $0
  puts "=" * 60
  puts "JSON Parser Example - Serialized: JSON Serialization"
  puts "=" * 60
  puts
  puts "NOTE: This example shows the planned API for Serialized."
  puts "The native extension support for parse_to_json is coming soon."
  puts

  test_cases = [
    ['"hello"', "hello"],
    ['42', 42],
    ['[1, 2, 3]', [1, 2, 3]],
    ['{"a": 1}', { "a" => 1 }],
  ]

  test_cases.each do |input, expected|
    puts
    puts "-" * 40
    puts "Input: #{input}"
    begin
      result = parse_json(input)
      status = result == expected ? "✓ PASS" : "✗ FAIL"
      puts "Expected: #{expected.inspect}, Got: #{result.inspect} - #{status}"
    rescue => e
      puts "Error: #{e.message}"
      puts "✗ FAIL"
    end
  end

  puts
  puts "=" * 60
  puts "Serialized Benefits for JSON:"
  puts "- Validates JSON structure"
  puts "- Normalizes formatting"
  puts "- Type-safe output (with typed classes)"
  puts "- Easy to cache serialized results"
  puts
  puts "Note: For simple JSON parsing, Serialized adds validation but"
  puts "the output is essentially the same as the input."
  puts "=" * 60
end
