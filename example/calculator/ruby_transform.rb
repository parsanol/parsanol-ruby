# frozen_string_literal: true

# Calculator Example - Ruby Transform: Ruby Transform (Parslet-Compatible)
#
# This example demonstrates Ruby Transform where:
# 1. Rust parser (parsanol-rs) does the fast parsing
# 2. Returns a generic tree (hash/array/string structure)
# 3. Ruby transform converts tree to Ruby objects
#
# This is the most flexible option and is 100% Parslet API compatible.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol'

# Step 1: Define the parser grammar
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

# Step 2: Define the AST classes
class IntExpr
  attr_reader :value

  def initialize(value)
    @value = value
  end

  def eval = @value

  def to_s = @value.to_s

  def ==(other)
    other.is_a?(IntExpr) && @value == other.value
  end
end

class BinOpExpr
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

# Step 3: Define the transform (Parslet-style)
class CalculatorTransform < Parsanol::Transform
  # Transform integer captures
  rule(int: simple(:n)) { IntExpr.new(Integer(n)) }

  # Transform binary operations
  # NOTE: The grammar wraps op with as(:op), so we get { op: { op: "+" } }
  # The outer :op is from add_op.as(:op), inner :op is from match('[+-]').as(:op)
  rule(left: simple(:l), op: { op: simple(:o) }, right: simple(:r)) do
    BinOpExpr.new(l, o, r)
  end

  # Handle binop wrapper
  rule(binop: simple(:b)) { b }
end

# Step 4: Parse and transform
def calculate(input)
  parser = CalculatorParser.new
  transform = CalculatorTransform.new

  # Ruby Transform: Parse in Rust, transform in Ruby
  tree = parser.parse(input)
  puts "Parse tree: #{tree.inspect}"

  ast = transform.apply(tree)
  puts "AST: #{ast}"

  result = ast.eval
  puts "Result: #{result}"

  result
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  test_cases = [
    ['42', 42],
    ['1 + 2', 3],
    ['3 * 4', 12],
    ['2 + 3 * 4', 14],
    ['(2 + 3) * 4', 20],
    ['10 - 3 - 2', 5], # Left associative: (10 - 3) - 2
    ['100 / 5 / 2', 10] # Left associative: (100 / 5) / 2
  ]

  puts '=' * 60
  puts 'Calculator Example - Ruby Transform: Ruby Transform'
  puts '=' * 60

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
      puts '✗ FAIL'
    end
  end
end

# Performance comparison note:
# - Ruby Transform is slower than Options B and C+ because transform happens in Ruby
# - But it's still faster than pure Ruby Parslet because parsing is in Rust
# - Use Ruby Transform for maximum flexibility and debugging
