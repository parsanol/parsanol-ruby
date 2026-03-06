# frozen_string_literal: true

# Dynamic Atoms Example
#
# Demonstrates runtime-determined parsing via callbacks.
# Dynamic atoms allow context-sensitive parsing where the grammar
# itself depends on the input or previously captured values.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'parsanol/parslet'
require 'pp'

puts "Dynamic Atoms Example"
puts "====================\n"

# ===========================================================================
# Example 1: Constant Callback
# ===========================================================================
puts "--- Example 1: Constant Callback ---\n"

# Always returns the same parser
parser = dynamic { str('hello') }

input = "hello world"
result = parser.parse(input)
puts "  Parsed successfully"
puts "  Matched: #{result.inspect}"

# ===========================================================================
# Example 2: Context-Sensitive Callback
# ===========================================================================
puts "\n--- Example 2: Context-Sensitive Callback ---\n"

# Different keyword based on preceding context
class LanguageParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:keyword) do
    dynamic do |_source, context|
      # Get remaining input from current position
      remaining = context.remaining

      # Look at the beginning of remaining to detect context
      if remaining.start_with?('def ')
        puts "    -> Detected Ruby context"
        str('def')
      elsif remaining.start_with?('lambda ')
        puts "    -> Detected Python context"
        str('lambda')
      else
        puts "    -> No context, using 'function'"
        str('function')
      end
    end
  end

  rule(:statement) { keyword >> str(' ') >> match('[a-z]+') }
  root :statement
end

test_cases = [
  ['def method', 'Ruby'],
  ['lambda x', 'Python'],
  ['function foo', 'JavaScript']
]

test_cases.each do |input, lang|
  puts "  Testing #{lang} input: #{input.inspect}"
  parser = LanguageParser.new
  begin
    result = parser.parse(input)
    puts "  ✓ Parsed: #{result.inspect}"
  rescue Parsanol::ParseFailed => e
    puts "  ✗ Parse error: #{e}"
  end
  puts
end

# ===========================================================================
# Example 3: Position-Based Callback
# ===========================================================================
puts "--- Example 3: Position-Based Callback ---\n"

class PositionParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:token) do
    dynamic do |_source, context|
      pos = context.pos
      input_length = context.input.length

      if pos == 0
        # First position: keyword
        str('let') | str('const') | str('var')
      elsif pos < input_length / 2
        # First half: identifier
        match('[a-zA-Z_][a-zA-Z0-9_]*')
      else
        # Second half: value
        match('\d+') | match('[a-z]+')
      end
    end
  end

  rule(:stmt) { token >> str(' ') >> token >> str('=') >> token }
  root :stmt
end

input = "let x=42"
puts "  Parsing: #{input.inspect}"
parser = PositionParser.new
begin
  result = parser.parse(input)
  puts "  ✓ Parsed: #{result.inspect}"
rescue Parsanol::ParseFailed => e
  puts "  ✗ Parse error: #{e}"
end

# ===========================================================================
# Example 4: Capture-Aware Callback
# ===========================================================================
puts "\n--- Example 4: Capture-Aware Callback ---\n"

class CaptureAwareParser < Parsanol::Parser
  include Parsanol::Parslet

  rule(:type) { match('[a-z]+').capture(:type) }
  rule(:name) { match('[a-z]+').capture(:name) }

  rule(:value) do
    dynamic do |_source, context|
      type = context[:type]
      puts "    -> Type capture: #{type.inspect}"

      case type
      when 'int' then match('\d+')
      when 'str' then match('[a-z]+')
      when 'bool' then str('true') | str('false')
      else match('[a-z]+')
      end.capture(:value)
    end
  end

  rule(:declaration) { type >> str(':') >> name >> str('=') >> value }
  root :declaration
end

test_cases = [
  ['int:count=42', 'int'],
  ['str:message=hello', 'str'],
  ['bool:enabled=true', 'bool']
]

test_cases.each do |input, expected_type|
  puts "  Parsing: #{input.inspect}"
  parser = CaptureAwareParser.new
  begin
    result = parser.parse(input)
    puts "  ✓ Parsed successfully"
    puts "    type: #{result[:type].inspect}"
    puts "    name: #{result[:name].inspect}"
    puts "    value: #{result[:value].inspect}"
  rescue Parsanol::ParseFailed => e
    puts "  ✗ Parse error: #{e}"
  end
  puts
end

# ===========================================================================
# Example 5: Configuration-Driven Parsing
# ===========================================================================
puts "\n--- Example 5: Configuration-Driven Parsing ---\n"

# Parser behavior can be configured at runtime
class ConfigurableParser < Parsanol::Parser
  include Parsanol::Parslet

  attr_accessor :strict_mode

  rule(:identifier) do
    dynamic do |_source, _context|
      if @strict_mode
        # Strict: lowercase only
        match('[a-z][a-z0-9_]*')
      else
        # Lenient: any identifier
        match('[a-zA-Z_][a-zA-Z0-9_]*')
      end
    end
  end

  root :identifier
end

puts "  Strict mode (lowercase only):"
parser = ConfigurableParser.new
parser.strict_mode = true

['variable', 'Variable'].each do |input|
  begin
    result = parser.parse(input)
    puts "    ✓ #{input.inspect} - accepted"
  rescue Parsanol::ParseFailed
    puts "    ✗ #{input.inspect} - rejected"
  end
end

puts "\n  Lenient mode (any case):"
parser = ConfigurableParser.new
parser.strict_mode = false

['variable', 'Variable'].each do |input|
  begin
    result = parser.parse(input)
    puts "    ✓ #{input.inspect} - accepted"
  rescue Parsanol::ParseFailed
    puts "    ✗ #{input.inspect} - rejected"
  end
end

# ===========================================================================
# Summary
# ===========================================================================
puts "\n--- Benefits of Dynamic Atoms ---"
puts "* Context-sensitive parsing at runtime"
puts "* Access to position, input, and captures"
puts "* Plugin architecture support"
puts "* Configuration-driven grammars"

puts "\n--- Backend Compatibility ---"
puts "* Packrat:  Native support (direct callback invocation)"
puts "* Bytecode: Packrat fallback (slower)"
puts "* Streaming: Packrat fallback (slower)"

puts "\n--- Performance Notes ---"
puts "* Native (Packrat): ~5% overhead per dynamic atom"
puts "* Callback should be fast - avoid I/O or heavy computation"

puts "\n--- DSL Helper ---"
puts "  dynamic { |source, context| parslet }  # Block returns parser"

puts "\n--- API Summary ---"
puts "  dynamic do |source, context|"
puts "    context.pos           # Current position"
puts "    context.captures[:n]  # Access captured values"
puts "    context.input         # Full input string"
puts "    context.remaining     # Remaining input from current position"
puts "    # Return a parslet atom"
puts "  end"
