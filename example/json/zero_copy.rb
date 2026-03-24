# frozen_string_literal: true

# JSON Parser Example - ZeroCopy: Mirrored Objects (Direct FFI)
#
# This example demonstrates ZeroCopy for parsing JSON:
# 1. Rust parser (parsanol-rs) does the parsing
# 2. Rust constructs typed JSON value objects
# 3. Direct Ruby object construction via FFI (no serialization!)
# 4. Maximum performance with zero-copy
#
# This option provides the best performance for JSON parsing.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require "parsanol"

# NOTE: This example requires:
# 1. ZeroCopy extension support for parse_to_objects
# 2. #[derive(RubyObject)] proc macro in Rust
# 3. Matching Ruby class definitions
#
# This serves as an API preview.

# Step 1: Define Ruby classes that mirror Rust struct definitions
module Json
  class Value
    def to_ruby
      raise NotImplementedError
    end
  end

  class Null < Value
    def to_ruby = nil
    def to_s = "null"
  end

  class Bool < Value
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def to_ruby = @value
    def to_s = @value ? "true" : "false"
  end

  class Number < Value
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def to_ruby = @value
    def to_s = @value.to_s
  end

  class String < Value
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def to_ruby = @value
    def to_s = "\"#{@value}\""
  end

  class Array < Value
    attr_reader :elements

    def initialize(elements)
      @elements = elements
    end

    def to_ruby = @elements.map(&:to_ruby)
    def to_s = "[#{@elements.join(', ')}]"
  end

  class Object < Value
    attr_reader :members

    def initialize(members)
      @members = members
    end

    def to_ruby = @members.transform_values(&:to_ruby)

    def to_s
      pairs = @members.map { |k, v| "\"#{k}\": #{v}" }
      "{#{pairs.join(', ')}}"
    end

    def [](key)
      @members[key]
    end

    def keys
      @members.keys
    end
  end
end

# Step 2: Define the parser with output type mapping
class JsonParser < Parsanol::Parser
  # Include ZeroCopy module (planned)
  # include Parsanol::ZeroCopy

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

  rule(:object) do
    str("{") >> space? >>
      (entry >> (comma >> entry).repeat).maybe.as(:object) >>
      space? >> str("}")
  end

  rule(:entry) do
    (string.as(:key) >> space? >> colon >> space? >> value.as(:val)).as(:entry)
  end

  rule(:array) do
    str("[") >> space? >>
      (value >> (comma >> value).repeat).maybe.as(:array) >>
      space? >> str("]")
  end

  rule(:string) do
    str('"') >> (
      (str("\\") >> any) | (str('"').absent? >> any)
    ).repeat.as(:string) >> str('"')
  end

  rule(:number) do
    (
      str("-").maybe >>
      (str("0") | (match("[1-9]") >> digit.repeat)) >>
      (str(".") >> digit.repeat(1)).maybe >>
      (match("[eE]") >> (str("+") | str("-")).maybe >> digit.repeat(1)).maybe
    ).as(:number)
  end

  rule(:true_value) { str("true").as(true) }
  rule(:false_value) { str("false").as(false) }
  rule(:null_value) { str("null").as(:null) }

  rule(:digit) { match("[0-9]") }
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }
  rule(:comma) { space? >> str(",") >> space? }
  rule(:colon) { str(":") }

  # Output type mapping (planned feature)
  # output_types(
  #   null: Json::Null,
  #   bool: Json::Bool,
  #   number: Json::Number,
  #   string: Json::String,
  #   array: Json::Array,
  #   object: Json::Object
  # )
end

# Step 3: Parse with direct object construction
def parse_json(input)
  JsonParser.new

  # ZeroCopy: Parse and get direct Ruby objects
  # NOTE: This requires native extension support
  # value = parser.parse(input)
  # # value is already a Json::String, Json::Number, etc.!
  # # No transform needed, no JSON serialization!

  # For demonstration, simulate what ZeroCopy would return
  value = simulate_parse(input)
  puts "Parsed: #{value.class}"
  puts "Value: #{value}"

  result = value.to_ruby
  puts "Ruby: #{result.inspect[0..100]}..."

  result
end

# Simulated parsing for demonstration
def simulate_parse(input)
  input = input.strip

  case input
  when "null"
    Json::Null.new
  when "true"
    Json::Bool.new(true)
  when "false"
    Json::Bool.new(false)
  when /^"(.*)"$/
    Json::String.new(Regexp.last_match(1))
  when /^-?\d+$/
    Json::Number.new(input.to_i)
  when /^-?\d+\.\d+$/
    Json::Number.new(input.to_f)
  when /^\[(.*)\]$/
    inner = Regexp.last_match(1).strip
    return Json::Array.new([]) if inner.empty?

    # Simple split for demonstration
    elements = inner.split(",").map { |e| simulate_parse(e.strip) }
    Json::Array.new(elements)
  when /^\{(.*)\}$/
    inner = Regexp.last_match(1).strip
    return Json::Object.new({}) if inner.empty?

    # Simple parse for demonstration
    members = {}
    inner.scan(/"([^"]+)":\s*([^,}]+)/) do |key, val|
      members[key] = simulate_parse(val.strip)
    end
    Json::Object.new(members)
  else
    raise "Cannot parse: #{input}"
  end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  puts "=" * 60
  puts "JSON Parser Example - ZeroCopy: Mirrored Objects"
  puts "=" * 60
  puts
  puts "NOTE: This example shows the planned API for ZeroCopy."
  puts "The native extension support for parse_to_objects is coming soon."
  puts

  test_cases = [
    ['"hello"', "hello"],
    ["42", 42],
    ["true", true],
    ["null", nil],
    ["[1, 2, 3]", [1, 2, 3]],
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
    rescue StandardError => e
      puts "Error: #{e.message}"
      puts "✗ FAIL"
    end
  end

  # Show type safety benefit
  puts
  puts "-" * 40
  puts "Type Safety Example:"
  json_obj = simulate_parse('{"name": "Alice", "age": 30}')
  puts "Parsed object type: #{json_obj.class}"
  puts "Name field type: #{json_obj['name'].class}"
  puts "Age field type: #{json_obj['age'].class}"

  puts
  puts "=" * 60
  puts "ZeroCopy Benefits for JSON:"
  puts "- FASTEST: No serialization overhead"
  puts "- Type-safe: Each JSON value type is a different class"
  puts "- Methods: Can add custom methods to Json::Object, etc."
  puts "- Zero-copy: Direct construction from Rust"
  puts
  puts "When to use ZeroCopy for JSON:"
  puts "- High-throughput JSON parsing"
  puts "- When you need typed access to values"
  puts "- When you want custom methods on JSON objects"
  puts "=" * 60
end

# Rust code that would be needed (for reference):
#
# // In parsanol-rs
# use parsanol_ruby_derive::RubyObject;
#
# #[derive(Debug, Clone, RubyObject)]
# #[ruby_class("Json::Value")]
# pub enum JsonValue {
#     #[ruby_variant("null")]
#     Null,
#
#     #[ruby_variant("bool")]
#     Bool(bool),
#
#     #[ruby_variant("number")]
#     Number(f64),
#
#     #[ruby_variant("string")]
#     String(String),
#
#     #[ruby_variant("array")]
#     Array(Vec<JsonValue>),
#
#     #[ruby_variant("object")]
#     Object(HashMap<String, JsonValue>),
# }
