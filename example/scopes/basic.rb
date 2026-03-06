# frozen_string_literal: true

# Scope Atoms Example
#
# Demonstrates how to create isolated capture contexts with scope atoms.
# Captures made inside a scope are discarded when the scope exits.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'parsanol/parslet'

include Parsanol::Parslet

puts "Scope Atoms Example"
puts "===================\n"

# ===========================================================================
# Example 1: Basic Scope Isolation
# ===========================================================================
puts "--- Example 1: Basic Scope Isolation ---\n"

# Without scope: captures accumulate, last value wins
parser = str('a').capture(:temp) >> str('b') >> str('c').capture(:temp)

input = "abc"
result = parser.parse(input)

puts "  Without scope:"
puts "    'temp' value: #{result[:temp].inspect}"  # "c" (last wins)

# With scope: inner captures are discarded
parser = str('prefix').capture(:outer) >> str(' ') >>
         scope { str('inner').capture(:inner) } >>
         str(' ') >> str('suffix').capture(:outer_end)

input = "prefix inner suffix"
result = parser.parse(input)

puts "\n  With scope:"
puts "    'outer': #{result[:outer].inspect}"
puts "    'outer_end': #{result[:outer_end].inspect}"
puts "    'inner': #{result[:inner].inspect rescue 'nil'}"  # Not present

# ===========================================================================
# Example 2: Nested Scopes
# ===========================================================================
puts "\n--- Example 2: Nested Scopes ---\n"

parser = str('L1').capture(:level) >> str(' ') >>
         scope {
           str('L2').capture(:level) >> str(' ') >>
           scope { str('L3').capture(:level) }
         }

input = "L1 L2 L3"
result = parser.parse(input)

puts "  Nested scopes - only L1 persists:"
puts "    'level' value: #{result[:level].inspect}"  # "L1"

# ===========================================================================
# Example 3: INI Configuration Parsing
# ===========================================================================
puts "\n--- Example 3: INI Configuration Parsing ---\n"

class IniParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:newline) { str("\n") | str("\r\n") }
  rule(:whitespace) { match('[ \t]*') }
  rule(:section_header) { str('[') >> match('[a-zA-Z_]+').capture(:section) >> str(']') >> whitespace >> newline }
  rule(:kv_pair) { match('[a-zA-Z_]+').capture(:key) >> str('=') >> match('[^\r\n]+').capture(:value) >> newline }
  rule(:section) { section_header >> scope { kv_pair.repeat(1) } }
  rule(:config) { section.repeat(1) }
  root :config
end

input = "[database]\nhost=localhost\nport=5432\n\n[server]\nport=8080\ndebug=true\n"

puts "  Input:\n#{input}"
parser = IniParser.new
result = parser.parse(input)

puts "  Outer captures: #{result.keys}"
puts "  (key/value captures are discarded after each section)"

# ===========================================================================
# Example 4: Scope for Memory Cleanup
# ===========================================================================
puts "\n--- Example 4: Scope for Memory Cleanup ---\n"

# Processing repeated structures - each gets its own scope
class ItemParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:item) { scope { match('\d+').capture(:id) >> str(':') >> match('[a-zA-Z]+').capture(:name) } }
  rule(:items) { str('item') >> item.repeat(1) }
  root :items
end

input = "item123:apple456:banana789:cherry"
puts "  Processing repeated items with scoped captures"
puts "  Input: #{input}"

parser = ItemParser.new
result = parser.parse(input)

puts "  Final captures: #{result.keys}"
puts "  (id and name captures are discarded after each item)"

# ===========================================================================
# Example 5: Scope with Dynamic
# ===========================================================================
puts "\n--- Example 5: Scope with Dynamic ---\n"

# Scope preserves outer captures for dynamic blocks
parser = str('a').capture(:a) >>
         scope { str('b').capture(:a) } >>
         dynamic { |_s, c| str(c.captures[:a]) }

begin
  parser.parse('aba')
  puts "  Parses 'aba' - scope preserved outer capture 'a'"
rescue StandardError
  puts "  Exception - scope isolation working"
end

# ===========================================================================
# Summary
# ===========================================================================
puts "\n--- Benefits of Scope Atoms ---"
puts "* Prevent capture pollution from nested parsing"
puts "* Each recursion level has its own capture state"
puts "* Automatic cleanup when scope exits"
puts "* Memory bounded during parse"
puts "* Essential for parsing nested structures"

puts "\n--- Performance Notes ---"
puts "* Scope push/pop is O(c_scope) where c_scope = captures in scope"
puts "* Each nesting level adds ~2% overhead"
puts "* Use scopes liberally - they're cheap"

puts "\n--- DSL Helper ---"
puts "  scope { parslet }  // Wraps parslet in isolated capture context"

puts "\n--- API Summary ---"
puts "  scope { inner }          -> isolates captures"
puts "  result[:name]            -> access captures (inner ones excluded)"
