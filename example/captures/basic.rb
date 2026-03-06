# frozen_string_literal: true

#
# Capture Atoms Example
#
# Demonstrates how to extract named values from parsed input using capture atoms.
# Captures work like named groups in regular expressions, but are integrated
# into the parsing grammar.

# NOTE: This example focuses on demonstrating the capture API.
# For production use, please refer to the existing capture example
# and the FFI documentation for more advanced patterns.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'parsanol/parslet'
require 'pp'

include Parsanol::Parslet

puts 'Capture Atoms Example'
puts "=====================\n"

# ===========================================================================
# Example 1: Basic Capture
# ===========================================================================
puts "--- Example 1: Basic Capture ---\n"

# Simple capture: match 'hello' and capture it
parser = str('hello').capture(:greeting)

input = 'hello'
result = parser.parse(input)
puts "  Input: #{input.inspect}"
puts "  Result: #{result.inspect} (a Slice)"
puts "  Result.to_s: #{result.to_s.inspect}"
# ===========================================================================
# Example 2: Multiple Captures in Sequence
# ===========================================================================
puts "\n--- Example 2: Multiple Captures in Sequence ---\n"

# Parse key=value pairs
kv_parser = match('[a-z]+').capture(:key) >>
            str('=') >>
            match('[a-zA-Z0-9]+').capture(:value)
input = 'name=Alice'
result = kv_parser.parse(input)
puts "  Input: #{input.inspect}"
puts "  Result: #{result.inspect}"
puts "  Key: #{result[:key]}"
puts "  Value: #{result[:value]}"
# ===========================================================================
# Example 3: Captures with Dynamic
# ===========================================================================
puts "\n--- Example 3: Captures with Dynamic ---\n"

# Use captured value in dynamic block
class TypeParser < Parsanol::Parser
  include Parsanol::Parslet

  root :declaration
  rule(:type) { match('[a-z]+').capture(:type) }
  rule(:value) do
    dynamic do |ctx|
      # Get captured type to determine value parser
      type_val = ctx[:type].to_s
      case type_val
      when 'int' then match('\d+')
      when 'str' then match('[a-z]+')
      when 'bool' then str('true') | str('false')
      else match('[a-z]+') # fallback
      end.capture(:value)
    end
  end
  rule(:declaration) { type >> str(':') >> match('[a-z]+').capture(:name) >> str('=') >> value }
end
test_cases = [
  ['int:count=42', 'int'],
  ['str:message=hello', 'str'],
  ['bool:enabled=true', 'bool']
]
puts "\nTesting type-driven parsing:"
test_cases.each_key do |input|
  puts "  Input: #{input.inspect}"
  parser = TypeParser.new
  result = parser.parse(input)
  puts '  ✓ Parsed successfully'
  puts "    type: #{result[:type]}"
  puts "    name: #{result[:name]}"
  puts "    value: #{result[:value]}"
end
# ===========================================================================
# Summary
# ===========================================================================
puts "\n--- Benefits of Capture Atoms ---"
puts '* Zero-copy: captures store offsets, not strings'
puts '* Works across all backends (Packrat, Streaming)'
puts '* Clean API: capture(name) method on atoms'
puts '* No AST construction needed for simple extraction'
puts "\n--- Performance Notes ---"
puts '* Captures add minimal overhead (~5% for heavy use)'
puts '* Capture lookup is O(n) where n = number of captures'
puts "\n--- API Summary ---"
puts '  atom.capture(:name)     -> captures match result'
puts '  result[:name]           -> retrieves captured value (Slice or Hash)'
puts '  result[:name].to_s      -> converts Slice to String'
puts '  context.captures[:name] -> in dynamic blocks'
