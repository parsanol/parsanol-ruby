# frozen_string_literal: true

# Calculator Example - Serialized: JSON Serialization
#
# This example demonstrates Serialized where:
# 1. Rust parser (parsanol-rs) does the parsing
# 2. Result is serialized to JSON
# 3. Ruby deserializes JSON to Ruby objects
#
# This option provides cross-language compatibility and structured output.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol'
require 'json'

# Check native extension availability
unless Parsanol::Native.available?
  puts '=' * 60
  puts 'Calculator Example - Serialized: JSON Serialization'
  puts '=' * 60
  puts
  puts 'ERROR: Native extension not available!'
  puts 'Please run: rake compile'
  puts '=' * 60
  exit 1
end

puts '=' * 60
puts 'Calculator Example - Serialized: JSON Serialization'
puts '=' * 60
puts
puts '✓ Native extension loaded successfully!'
puts

# Step 1: Define the parser grammar (same as RubyTransform)
class CalculatorParser < Parsanol::Parser
  root :expression

  rule(:expression) do
    (term.as(:left) >> add_op.as(:op) >> expression.as(:right)).as(:binop) |
      term
  end

  rule(:term) do
    (factor.as(:left) >> mult_op.as(:op) >> term.as(:right)).as(:binop) |
      factor
  end

  rule(:factor) do
    (lparen >> expression >> rparen) |
      number
  end

  rule(:number) do
    match('[0-9]').repeat(1).as(:int) >> space?
  end

  rule(:add_op) { match('[+-]').as(:op) >> space? }
  rule(:mult_op) { match('[*/]').as(:op) >> space? }

  rule(:lparen) { str('(') >> space? }
  rule(:rparen) { str(')') >> space? }
  rule(:space?) { match('\s').repeat }
end

# Step 2: Define AST classes
class Expr
  def eval
    raise NotImplementedError
  end
end

class NumberExpr < Expr
  attr_reader :value

  def initialize(value)
    @value = value
  end

  def eval = @value
  def to_s = @value.to_s
end

class BinOpExpr < Expr
  attr_reader :left, :op, :right

  def initialize(left, op, right)
    @left = left
    @op = op
    @right = right
  end

  def eval
    left_val = @left.eval
    right_val = @right.eval

    case @op
    when '+' then left_val + right_val
    when '-' then left_val - right_val
    when '*' then left_val * right_val
    when '/' then left_val / right_val
    end
  end

  def to_s
    "(#{@left} #{@op} #{@right})"
  end
end

# Step 3: Native JSON parser
def parse_json_to_expr(data)
  case data
  when Hash
    if data.key?('int')
      int_val = data['int']
      int_val = int_val.first if int_val.is_a?(Array)
      NumberExpr.new(Integer(int_val))
    elsif data.key?('binop')
      binop = data['binop']

      # Handle both array and hash formats
      if binop.is_a?(Array)
        # Array format: [{"left": ...}, {"op": ...}, {"right": ...}]
        left_data = binop.find { |e| e.is_a?(Hash) && e.key?('left') }&.dig('left')
        op_data = binop.find { |e| e.is_a?(Hash) && e.key?('op') }&.dig('op')
        right_data = binop.find { |e| e.is_a?(Hash) && e.key?('right') }&.dig('right')
      else
        # Hash format
        left_data = binop['left']
        op_data = binop['op']
        right_data = binop['right']
      end

      op = extract_op(op_data)
      left = parse_json_to_expr(left_data)
      right = parse_json_to_expr(right_data)
      BinOpExpr.new(left, op, right)
    else
      # Try to find the first value that's parseable
      data.each_value do |v|
        result = parse_json_to_expr(v)
        return result if result
      end
      nil
    end
  when Array
    # Arrays often contain [value, whitespace] - extract the value
    # Or they could be [elem1, elem2, elem3] format
    result = nil
    data.each do |elem|
      parsed = parse_json_to_expr(elem)
      result = parsed if parsed
    end
    result
  when String
    # Could be a number string
    Integer(data, exception: false)
  end
end

def extract_op(data)
  case data
  when Hash
    if data.key?('op')
      extract_op(data['op'])
    else
      extract_op(data.values.first)
    end
  when Array
    # Find the op value in the array
    data.each do |elem|
      result = extract_op(elem)
      return result if result.is_a?(String) && result.match?(%r{^[+\-*/]$})
    end
    nil
  when String
    data
  else
    data.to_s
  end
end

# Step 4: Parse using native extension
def calculate(input)
  parser = CalculatorParser.new

  # Serialized: Parse using native extension and get JSON
  grammar_json = Parsanol::Native.serialize_grammar(parser.root)
  json_string = Parsanol::Native.parse_to_json(grammar_json, input)

  puts "Native JSON: #{json_string}"

  # Deserialize to Ruby objects
  data = JSON.parse(json_string)
  expr = parse_json_to_expr(data)

  if expr
    puts "AST: #{expr}"
    result = expr.eval
  else
    # Fall back to pure Ruby parsing
    tree = parser.parse(input)
    transform = CalculatorTransform.new
    ast = transform.apply(tree)
    puts "AST (fallback): #{ast}"
    result = ast.eval
  end
  puts "Result: #{result}"
  result
end

# Transform class for fallback
class CalculatorTransform < Parsanol::Transform
  rule(int: simple(:n)) { NumberExpr.new(Integer(n)) }
  rule(left: simple(:l), op: { op: simple(:o) }, right: simple(:r)) do
    BinOpExpr.new(l, o, r)
  end
  rule(binop: simple(:b)) { b }
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  test_cases = [
    ['42', 42],
    ['1 + 2', 3],
    ['3 * 4', 12],
    ['2 + 3 * 4', 14],
    ['(2 + 3) * 4', 20]
  ]

  test_cases.each do |input, expected|
    puts
    puts '-' * 40
    puts "Input: #{input}"
    begin
      result = calculate(input)
      status = result == expected ? '✓ PASS' : '✗ FAIL'
      puts "Expected: #{expected}, Got: #{result} - #{status}"
    rescue StandardError => e
      puts "Error: #{e.message}"
      puts e.backtrace.first(3).join("\n")
      puts '✗ FAIL'
    end
  end

  puts
  puts '=' * 60
  puts 'Serialized Benefits:'
  puts '- Cross-language: Same JSON works for Python, JavaScript, etc.'
  puts '- Native performance: All parsing done in Rust'
  puts '- Structured output with type information'
  puts '- Easy to cache/store results'
  puts '=' * 60
end
