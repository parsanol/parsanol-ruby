# frozen_string_literal: true

# Balanced Parentheses Parser Example - RubyTransform
#
# This example demonstrates parsing balanced parentheses expressions.
# Shows recursive grammar rules and validation.
#
# Run with: ruby -Ilib example/balanced_parens_ruby_transform.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol'

# Step 1: Define the balanced parentheses grammar
# Using a PEG-friendly approach: parse multiple balanced groups
class BalancedParensParser < Parsanol::Parser
  root :content

  # Content: zero or more balanced groups
  rule(:content) do
    balanced.repeat
  end

  # Balanced: a parenthesized group that may contain more groups
  rule(:balanced) do
    str('(') >> content >> str(')')
  end
end

# Step 2: Node classes
class ParenExpr
  attr_reader :inner

  def initialize(inner)
    @inner = inner
  end

  def balanced?
    true
  end

  def to_s
    "(#{@inner})"
  end

  def depth
    1 + (@inner.respond_to?(:depth) ? @inner.depth : 0)
  end
end

class EmptyExpr
  def balanced?
    true
  end

  def to_s
    ''
  end

  def depth
    0
  end
end

class SequenceExpr
  attr_reader :exprs

  def initialize(exprs)
    @exprs = exprs
  end

  def balanced?
    @exprs.all?(&:balanced?)
  end

  def to_s
    @exprs.join
  end

  def depth
    @exprs.map(&:depth).max || 0
  end
end

# Step 3: Parse and build AST
def parse_balanced(input)
  parser = BalancedParensParser.new

  tree = parser.parse(input)
  puts "Parse tree: #{tree.inspect}"

  # Build AST from tree
  ast = build_ast(tree)
  puts "AST: #{ast}"
  puts "Balanced: #{ast.balanced?}"
  puts "Max depth: #{ast.depth}"

  ast
rescue Parsanol::ParseFailed => e
  puts "Parse failed: #{e.message}"
  nil
rescue SystemStackError
  puts 'Stack overflow - grammar too complex for input'
  nil
end

def build_ast(tree)
  # Handle nil and empty
  return EmptyExpr.new if tree.nil?
  return EmptyExpr.new if tree.to_s.empty?

  if tree.is_a?(Array)
    exprs = tree.map { |t| build_ast(t) }.grep_v(EmptyExpr)
    return EmptyExpr.new if exprs.empty?
    return exprs.first if exprs.length == 1

    SequenceExpr.new(exprs)
  elsif tree.is_a?(Hash)
    if tree[:balanced]
      inner = build_ast(tree[:balanced])
      ParenExpr.new(inner)
    elsif tree[:content]
      build_ast(tree[:content])
    else
      EmptyExpr.new
    end
  else
    EmptyExpr.new
  end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  puts '=' * 60
  puts 'Balanced Parentheses Parser - RubyTransform'
  puts '=' * 60
  puts

  test_cases = [
    '',              # Empty - balanced
    '()',            # Simple - balanced
    '(())',          # Nested - balanced
    '(()())',       # Multiple - balanced
    '((()))',       # Deeply nested - balanced
    '(()())()',     # Multiple groups - balanced
    '(())(())',     # Two groups - balanced
    '(',             # Unbalanced - should fail
    ')',             # Unbalanced - should fail
    '(()',           # Unbalanced - should fail
    '())',           # Unbalanced - should fail
    '((())' # Unbalanced - should fail
  ]

  test_cases.each do |input|
    puts '-' * 40
    puts "Input: '#{input}'"
    ast = parse_balanced(input)
    if ast
      puts "Result: #{ast.balanced? ? '✓ BALANCED' : '✗ UNBALANCED'}"
    else
      puts 'Result: ✗ PARSE FAILED'
    end
    puts
  end
end
