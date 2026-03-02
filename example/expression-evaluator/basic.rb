# Expression Evaluator - Ruby Implementation
#
# A complete expression parser with operator precedence, variables,
# and function calls. Demonstrates building a practical calculator.
#
# Run with: ruby example/expression-evaluator/basic.rb

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol/parslet'

# Expression parser with full operator precedence
class ExpressionParser < Parsanol::Parser
  root :expression

  # Comparison (lowest precedence)
  rule(:expression) { comparison }

  rule(:comparison) {
    addition.as(:left) >>
    ((match('==|!=|<=|>=|<>').as(:op) | str('<') | str('>')).as(:op) >>
     addition.as(:right)).repeat(1) |
    addition
  }

  # Addition/subtraction
  rule(:addition) {
    multiplication.as(:left) >>
    (match('[+-]').as(:op) >> multiplication.as(:right)).repeat(1) |
    multiplication
  }

  # Multiplication/division/modulo
  rule(:multiplication) {
    power.as(:left) >>
    (match('[*/%]').as(:op) >> power.as(:right)).repeat(1) |
    power
  }

  # Exponentiation (right associative)
  rule(:power) {
    unary.as(:left) >>
    (str('^').as(:op) >> power.as(:right)).maybe |
    unary
  }

  # Unary operators
  rule(:unary) {
    (str('-').as(:op) >> unary.as(:operand)).as(:unary) |
    (str('!').as(:op) >> unary.as(:operand)).as(:unary) |
    primary
  }

  # Primary: number, function call, variable, or parenthesized expression
  rule(:primary) {
    funcall |
    number |
    variable |
    lparen >> expression >> rparen
  }

  rule(:number) {
    (match('[0-9]').repeat(1) >> str('.') >> match('[0-9]').repeat(1) |
     match('[0-9]').repeat(1)).as(:number) >> space?
  }

  rule(:variable) {
    (match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat).as(:variable) >> space?
  }

  rule(:funcall) {
    (match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat).as(:name) >>
    lparen >>
    arglist.as(:args) >>
    rparen
  }

  rule(:arglist) {
    (expression >> (comma >> expression).repeat).maybe
  }

  rule(:lparen) { str('(') >> space? }
  rule(:rparen) { str(')') >> space? }
  rule(:comma) { str(',') >> space? }
  rule(:space?) { match('\s').repeat }
end

# AST node classes
Number = Struct.new(:value) do
  def eval(_ctx)
    value
  end
end

Variable = Struct.new(:name) do
  def eval(ctx)
    ctx.variables.fetch(name) { raise "Unknown variable: #{name}" }
  end
end

BinaryOp = Struct.new(:left, :op, :right) do
  def eval(ctx)
    l = left.eval(ctx)
    r = right.eval(ctx)

    case op
    when '+' then l + r
    when '-' then l - r
    when '*' then l * r
    when '/' then l / r
    when '%' then l % r
    when '^' then l ** r
    when '==' then l == r ? 1.0 : 0.0
    when '!=' then l != r ? 1.0 : 0.0
    when '<' then l < r ? 1.0 : 0.0
    when '>' then l > r ? 1.0 : 0.0
    when '<=' then l <= r ? 1.0 : 0.0
    when '>=' then l >= r ? 1.0 : 0.0
    else raise "Unknown operator: #{op}"
    end
  end
end

UnaryOp = Struct.new(:op, :operand) do
  def eval(ctx)
    v = operand.eval(ctx)
    case op
    when '-' then -v
    when '!' then v == 0 ? 1.0 : 0.0
    else raise "Unknown unary operator: #{op}"
    end
  end
end

FunctionCall = Struct.new(:name, :args) do
  def eval(ctx)
    arg_values = args.map { |a| a.eval(ctx) }

    if ctx.functions.key?(name)
      ctx.functions[name].call(arg_values)
    else
      raise "Unknown function: #{name}"
    end
  end
end

# Transform parse tree to AST
class ExpressionTransform < Parsanol::Transform
  rule(number: simple(:n)) { Number.new(n.to_s.to_f) }
  rule(variable: simple(:v)) { Variable.new(v.to_s) }

  rule(name: simple(:n), args: simple(:a)) {
    FunctionCall.new(n.to_s, a.is_a?(Array) ? a : [a])
  }
  rule(name: simple(:n), args: sequence(:a)) {
    FunctionCall.new(n.to_s, a)
  }

  rule(left: simple(:l)) { l }

  rule(left: simple(:l), op: simple(:o), right: simple(:r)) {
    BinaryOp.new(l, o.to_s, r)
  }

  rule(unary: { op: simple(:o), operand: simple(:e) }) {
    UnaryOp.new(o.to_s, e)
  }
end

# Evaluation context with variables and functions
class EvalContext
  attr_accessor :variables, :functions

  def initialize
    @variables = {
      'PI' => Math::PI,
      'E' => Math::E
    }

    @functions = {
      'sin' => ->(args) { Math.sin(args[0] || 0) },
      'cos' => ->(args) { Math.cos(args[0] || 0) },
      'tan' => ->(args) { Math.tan(args[0] || 0) },
      'sqrt' => ->(args) { Math.sqrt(args[0] || 0) },
      'abs' => ->(args) { (args[0] || 0).abs },
      'floor' => ->(args) { (args[0] || 0).floor },
      'ceil' => ->(args) { (args[0] || 0).ceil },
      'round' => ->(args) { (args[0] || 0).round },
      'min' => ->(args) { [args[0] || 0, args[1] || 0].min },
      'max' => ->(args) { [args[0] || 0, args[1] || 0].max },
      'log' => ->(args) { Math.log(args[0] || 1) },
      'exp' => ->(args) { Math.exp(args[0] || 0) }
    }
  end

  def set(name, value)
    @variables[name] = value
  end
end

# Evaluate an expression string
def evaluate(str, ctx = EvalContext.new)
  parser = ExpressionParser.new
  transform = ExpressionTransform.new

  tree = parser.parse(str)
  ast = transform.apply(tree)

  # Handle BinaryOp chains with multiple ops
  if ast.is_a?(Array) && ast.length == 1
    ast = ast.first
  end

  # Reduce left-associative chains
  while ast.is_a?(Hash) && ast.key?(:left)
    left = ast[:left]
    if left.is_a?(Hash) && left.key?(:left)
      # Nested chain - flatten
      inner = evaluate_helper(left, ctx)
      ast = BinaryOp.new(inner, ast[:op], ast[:right])
    else
      ast = BinaryOp.new(left, ast[:op], ast[:right])
    end
  end

  ast.eval(ctx)
rescue => e
  "Error: #{e.message}"
end

def evaluate_helper(node, ctx)
  return node unless node.is_a?(Hash)

  if node.key?(:left)
    left = evaluate_helper(node[:left], ctx)
    right = evaluate_helper(node[:right], ctx)
    BinaryOp.new(left, node[:op], right)
  else
    node
  end
end

# Main demo
if __FILE__ == $0
  ctx = EvalContext.new
  ctx.set('x', 10.0)
  ctx.set('y', 5.0)

  puts "Expression Evaluator Example"
  puts "=" * 40
  puts
  puts "Variables: x = #{ctx.variables['x']}, y = #{ctx.variables['y']}"
  puts "Constants: PI = #{ctx.variables['PI']}, E = #{ctx.variables['E']}"
  puts

  expressions = [
    "1 + 2 * 3",
    "(1 + 2) * 3",
    "2 ^ 3 ^ 2",
    "x + y",
    "x * y - 5",
    "sin(PI / 2)",
    "sqrt(16)",
    "max(x, y)",
    "x > y",
    "min(sin(0), cos(0))"
  ]

  printf "%-25s | %s\n", "Expression", "Result"
  puts "-" * 40

  expressions.each do |expr|
    result = evaluate(expr, ctx)
    printf "%-25s | %s\n", expr, result
  end

  # Command line argument
  if ARGV.length > 0
    expr = ARGV.join(' ')
    puts
    puts "Evaluating: #{expr}"
    puts "Result: #{evaluate(expr, ctx)}"
  end
end
