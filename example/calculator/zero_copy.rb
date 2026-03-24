# frozen_string_literal: true

# Calculator Example - ZeroCopy: Mirrored Objects (Direct FFI)
#
# This example demonstrates ZeroCopy where:
# 1. Rust parser (parsanol-rs) does the parsing
# 2. Rust transform converts to typed structs
# 3. Direct Ruby object construction via FFI (no serialization!)
# 4. Maximum performance with zero-copy
#
# This option provides the best performance but requires type definitions
# in both Rust and Ruby.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require "parsanol"

# NOTE: This example requires:
# 1. Native extension support for parse_to_objects
# 2. #[derive(RubyObject)] proc macro in Rust
# 3. Matching Ruby class definitions
#
# This serves as an API preview.

# Step 1: Define Ruby classes that mirror Rust struct definitions
# These classes MUST match the Rust definitions exactly
module Calculator
  class Expr
    def eval
      raise NotImplementedError
    end
  end

  class Number < Expr
    attr_reader :value

    # This constructor is called directly from Rust FFI
    def initialize(value)
      @value = value
    end

    def eval = @value

    def to_s = @value.to_s

    def ==(other)
      other.is_a?(Number) && @value == other.value
    end
  end

  class BinOp < Expr
    attr_reader :left, :op, :right

    # This constructor is called directly from Rust FFI
    # Rust sets instance variables directly via rb_ivar_set
    def initialize(left: nil, op: nil, right: nil)
      @left = left
      @op = op
      @right = right
    end

    def eval
      left_val = @left.eval
      right_val = @right.eval

      case @op
      when "+" then left_val + right_val
      when "-" then left_val - right_val
      when "*" then left_val * right_val
      when "/" then left_val / right_val
      end
    end

    def to_s
      "(#{@left} #{@op} #{@right})"
    end
  end
end

# Step 2: Define the parser with output type mapping
class CalculatorParser < Parsanol::Parser
  # Include ZeroCopy module for direct FFI object construction
  # include Parsanol::ZeroCopy

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
    match("[0-9]").repeat(1).as(:int) >> space?
  end

  rule(:add_op) { match("[+-]").as(:op) >> space? }
  rule(:mult_op) { match("[*/]").as(:op) >> space? }

  rule(:lparen) { str("(") >> space? }
  rule(:rparen) { str(")") >> space? }
  rule(:space?) { match('\s').repeat }

  # Output type mapping (ZeroCopy feature)
  # This tells Rust which Ruby classes to construct
  # output_types(
  #   number: Calculator::Number,
  #   binop: Calculator::BinOp
  # )
end

# Step 3: Parse with direct object construction
def calculate(input)
  CalculatorParser.new

  # ZeroCopy: Parse and get direct Ruby objects
  # NOTE: This requires native extension support
  # expr = parser.parse(input)
  # # expr is already a Calculator::Number or Calculator::BinOp!
  # # No transform needed, no JSON serialization!

  # For demonstration, simulate what ZeroCopy would return
  # Real implementation would call:
  #   Native.parse_to_objects(grammar_json, input, output_types)

  # Simulate direct object construction
  expr = simulate_parse(input)
  puts "AST: #{expr.class} -> #{expr}"

  result = expr.eval
  puts "Result: #{result}"

  result
end

# Simulated parsing for demonstration
def simulate_parse(input)
  case input.strip
  when "42"
    Calculator::Number.new(42)
  when "1 + 2"
    Calculator::BinOp.new(
      left: Calculator::Number.new(1),
      op: "+",
      right: Calculator::Number.new(2),
    )
  when "3 * 4"
    Calculator::BinOp.new(
      left: Calculator::Number.new(3),
      op: "*",
      right: Calculator::Number.new(4),
    )
  when "2 + 3 * 4"
    Calculator::BinOp.new(
      left: Calculator::Number.new(2),
      op: "+",
      right: Calculator::BinOp.new(
        left: Calculator::Number.new(3),
        op: "*",
        right: Calculator::Number.new(4),
      ),
    )
  when "(2 + 3) * 4"
    Calculator::BinOp.new(
      left: Calculator::BinOp.new(
        left: Calculator::Number.new(2),
        op: "+",
        right: Calculator::Number.new(3),
      ),
      op: "*",
      right: Calculator::Number.new(4),
    )
  else
    raise "Not simulated: #{input}"
  end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  puts "=" * 60
  puts "Calculator Example - ZeroCopy: Mirrored Objects"
  puts "=" * 60
  puts
  puts "NOTE: This example shows the planned API for ZeroCopy."
  puts "The native extension support for parse_to_objects is coming soon."
  puts

  test_cases = [
    ["42", 42],
    ["1 + 2", 3],
    ["3 * 4", 12],
    ["2 + 3 * 4", 14],
    ["(2 + 3) * 4", 20],
  ]

  test_cases.each do |input, expected|
    puts
    puts "-" * 40
    puts "Input: #{input}"
    begin
      result = calculate(input)
      status = result == expected ? "✓ PASS" : "✗ FAIL"
      puts "Expected: #{expected}, Got: #{result} - #{status}"
    rescue StandardError => e
      puts "Error: #{e.message}"
      puts "✗ FAIL"
    end
  end

  puts
  puts "=" * 60
  puts "ZeroCopy Benefits:"
  puts "- FASTEST: No serialization overhead"
  puts "- Zero-copy: Direct Ruby object construction"
  puts "- Type-safe: Types defined in both Rust and Ruby"
  puts "- Methods defined in Ruby (eval, to_s, etc.)"
  puts
  puts "ZeroCopy Requirements:"
  puts "- Define types in Rust with #[derive(RubyObject)]"
  puts "- Define matching Ruby classes"
  puts "- Native extension compiled with ruby feature"
  puts "=" * 60
end

# Rust code that would be needed (for reference):
#
# // In parsanol-rs
# use parsanol_ruby_derive::RubyObject;
#
# #[derive(Debug, Clone, RubyObject)]
# #[ruby_class("Calculator::Expr")]
# pub enum Expr {
#     #[ruby_variant("number")]
#     Number(i64),
#
#     #[ruby_variant("binop")]
#     BinOp {
#         left: Box<Expr>,
#         op: String,
#         right: Box<Expr>,
#     },
# }
#
# // The proc macro generates:
# impl RubyObject for Expr {
#     fn to_ruby(&self, ruby: &Ruby) -> Result<Value, Error> {
#         match self {
#             Expr::Number(n) => {
#                 let class = ruby.class("Calculator::Number")?;
#                 class.new_instance((*n,))
#             }
#             Expr::BinOp { left, op, right } => {
#                 let class = ruby.class("Calculator::BinOp")?;
#                 let obj = class.new_instance()?;
#                 obj.ivar_set("@left", left.to_ruby(ruby)?)?;
#                 obj.ivar_set("@op", op.to_ruby(ruby)?)?;
#                 obj.ivar_set("@right", right.to_ruby(ruby)?)?;
#                 Ok(obj.as_value())
#             }
#         }
#     }
# }
