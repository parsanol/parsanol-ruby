# Boolean Algebra Parser Example - RubyTransform: Ruby Transform
#
# This example demonstrates parsing boolean expressions with AND/OR operators.
# Shows operator precedence, parentheses handling, and evaluation.
#
# Run with: ruby -Ilib example/boolean_algebra_ruby_transform.rb

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol'

# Step 1: Define the parser grammar
class BooleanAlgebraParser < Parsanol::Parser
  root :expression

  rule(:expression) { or_expr }

  # OR expression (lowest precedence)
  rule(:or_expr) {
    (and_expr.as(:left) >> or_op >> or_expr.as(:right)).as(:or) |
    and_expr
  }

  # AND expression (higher precedence)
  rule(:and_expr) {
    (primary.as(:left) >> and_op >> and_expr.as(:right)).as(:and) |
    primary
  }

  # Primary: variable or parenthesized expression
  rule(:primary) {
    lparen >> expression >> rparen |
    variable
  }

  rule(:variable) { match['a-z'].repeat(1).as(:var) >> digit.repeat(1).as(:num) }
  rule(:digit) { match('[0-9]') }

  rule(:or_op) { spaces >> str('or') >> spaces }
  rule(:and_op) { spaces >> str('and') >> spaces }

  rule(:lparen) { str('(') >> spaces? }
  rule(:rparen) { spaces? >> str(')') }
  rule(:spaces) { match('\s').repeat(1) }
  rule(:spaces?) { match('\s').repeat }
end

# Step 2: Define AST classes
class BoolExpr
  def eval(bindings)
    raise NotImplementedError
  end
end

class VarExpr < BoolExpr
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def eval(bindings)
    bindings[@name] || raise("Unknown variable: #{@name}")
  end

  def to_s = @name
end

class AndExpr < BoolExpr
  attr_reader :left, :right

  def initialize(left, right)
    @left = left
    @right = right
  end

  def eval(bindings)
    @left.eval(bindings) && @right.eval(bindings)
  end

  def to_s = "(#{@left} AND #{@right})"
end

class OrExpr < BoolExpr
  attr_reader :left, :right

  def initialize(left, right)
    @left = left
    @right = right
  end

  def eval(bindings)
    @left.eval(bindings) || @right.eval(bindings)
  end

  def to_s = "(#{@left} OR #{@right})"
end

# Step 3: Define transform
class BooleanTransform < Parsanol::Transform
  rule(var: simple(:v), num: simple(:n)) { VarExpr.new("#{v}#{n}") }
  rule(and: simple(:a)) { a }
  rule(or: simple(:o)) { o }
  rule(left: simple(:l), right: simple(:r)) {
    # This handles the case where there's no explicit operator
    l  # Just return the left side for non-binary expressions
  }
end

# Transform that handles binary expressions properly
class BooleanTransformFull < Parsanol::Transform
  rule(var: simple(:v), num: simple(:n)) { VarExpr.new("#{v}#{n}") }

  rule(left: simple(:l), right: simple(:r)) {
    # This catches expressions without explicit and/or tags
    # Return just the first one (this is a simplified handling)
    l
  }

  # These would need the actual tree structure to work correctly
  rule(and: subtree(:a)) {
    if a.is_a?(Hash) && a[:left] && a[:right]
      AndExpr.new(transform(a[:left]), transform(a[:right]))
    else
      a
    end
  }

  rule(or: subtree(:o)) {
    if o.is_a?(Hash) && o[:left] && o[:right]
      OrExpr.new(transform(o[:left]), transform(o[:right]))
    else
      o
    end
  }
end

# Manual AST builder for demonstration
def build_ast(tree)
  case tree
  when Hash
    if tree[:var] && tree[:num]
      VarExpr.new("#{tree[:var]}#{tree[:num]}")
    elsif tree[:and]
      build_and_expr(tree[:and])
    elsif tree[:or]
      build_or_expr(tree[:or])
    else
      # Try to extract from nested structure
      tree.each_value do |v|
        result = build_ast(v)
        return result if result.is_a?(BoolExpr)
      end
      nil
    end
  when Array
    build_ast(tree.first)
  when Parsanol::Slice
    nil
  else
    nil
  end
end

def build_and_expr(data)
  case data
  when Hash
    left = build_ast(data[:left])
    right = build_ast(data[:right])
    if left && right
      AndExpr.new(left, right)
    else
      build_ast(data)
    end
  else
    build_ast(data)
  end
end

def build_or_expr(data)
  case data
  when Hash
    left = build_ast(data[:left])
    right = build_ast(data[:right])
    if left && right
      OrExpr.new(left, right)
    else
      build_ast(data)
    end
  else
    build_ast(data)
  end
end

# Step 4: Parse and transform
def parse_boolean(input)
  parser = BooleanAlgebraParser.new

  # RubyTransform: Parse and get tree
  tree = parser.parse(input)
  puts "Parse tree: #{tree.inspect}"

  # Build AST
  ast = build_ast(tree)
  puts "AST: #{ast.to_s}"

  ast
end

# Example usage
if __FILE__ == $0
  puts "=" * 60
  puts "Boolean Algebra Parser - RubyTransform"
  puts "=" * 60
  puts

  expressions = [
    "var1",
    "var1 and var2",
    "var1 or var2",
    "var1 and var2 or var3",
    "var1 or var2 and var3",
    "(var1 or var2) and var3",
  ]

  expressions.each do |expr_str|
    puts "-" * 40
    puts "Input: #{expr_str}"
    begin
      ast = parse_boolean(expr_str)
    rescue => e
      puts "Error: #{e.message}"
    end
    puts
  end

  # Demonstrate evaluation
  puts "=" * 60
  puts "Evaluation Example"
  puts "=" * 60

  bindings = { "var1" => true, "var2" => false, "var3" => true }
  puts "Bindings: var1=true, var2=false, var3=true"
  puts

  eval_exprs = [
    "var1 and var2",
    "var1 or var2",
    "var1 and var3",
    "(var1 or var2) and var3",
  ]

  eval_exprs.each do |expr_str|
    begin
      ast = parse_boolean(expr_str)
      result = ast.eval(bindings)
      puts "  #{expr_str} = #{result}"
    rescue => e
      puts "  #{expr_str} = ERROR: #{e.message}"
    end
    puts
  end
end
