# frozen_string_literal: true

# Infix expression parser using precedence climbing algorithm.
# Parses mathematical-style expressions with configurable operators.
#
# @example Basic usage
#   element = match('[0-9]').repeat(1)
#   operations = [
#     [str('+'), 1, :left],
#     [str('*'), 2, :left]
#   ]
#   infix = Parsanol::Atoms::Infix.new(element, *operations)
#
# Inspired by Parslet (MIT License).
# Algorithm reference: http://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing/

class Parsanol::Atoms::Infix < Parsanol::Atoms::Base
  attr_reader :base_element, :operator_table, :result_combiner

  # Creates a new infix expression parser.
  #
  # @param base_element [Parsanol::Atoms::Base] parser for atomic operands
  # @param operations [Array<Array>] operator definitions [atom, precedence, associativity]
  # @yield block to combine left, operator, right into result
  def initialize(base_element, operations, &combiner)
    super()
    @base_element = base_element
    @operator_table = operations
    @result_combiner = combiner || default_combiner
  end

  # Attempts to parse an infix expression from the source.
  #
  # @param source [Parsanol::Source] input source
  # @param context [Parsanol::Atoms::Context] parsing context
  # @param consume_all [Boolean] whether to consume all input
  # @return [Array] success/error tuple
  def try(source, context, consume_all)
    catch(:parse_error) do
      raw_result = climb_precedence(source, context, consume_all)
      structured_result = build_result_tree(raw_result)
      return succ(structured_result)
    end
  end

  private

  # Default combiner creates nested hash structure
  def default_combiner
    ->(left_side, operator, right_side) do
      { left: left_side, op: operator, right: right_side }
    end
  end

  # Converts flat array representation to nested structure.
  # Input: ['1', '+', ['2', '*', '3']]
  # Output: { left: '1', op: '+', right: { left: '2', op: '*', right: '3' } }
  #
  # @param expression [Object] array or leaf value
  # @return [Object] structured result
  def build_result_tree(expression)
    return expression unless expression.is_a?(Array)

    combiner = @result_combiner
    accumulator = expression.shift

    until expression.empty?
      operator_token, right_operand = expression.shift(2)

      if right_operand.is_a?(Array)
        # Recursively process nested expressions
        right_operand = build_result_tree(right_operand)
      end

      accumulator = combiner.call(accumulator, operator_token, right_operand)
    end

    accumulator
  end

  # Main precedence climbing loop.
  # Parses operands and operators, respecting precedence and associativity.
  #
  # @param source [Parsanol::Source] input source
  # @param context [Parsanol::Atoms::Context] parsing context
  # @param consume_all [Boolean] consume all flag
  # @param min_precedence [Integer] minimum precedence to continue (default: 1)
  # @return [Object] parsed expression
  def climb_precedence(source, context, consume_all, min_precedence = 1)
    element_parser = @base_element
    expression_parts = []

    # Must match at least one element to start
    ok, first_value = element_parser.apply(source, context, false)
    unless ok
      throw :parse_error,
            context.err(self, source, "Expected #{element_parser.inspect}", [first_value])
    end

    expression_parts << flatten(first_value, true)

    # Continue while operators match
    loop do
      saved_position = source.bytepos
      operator_match, precedence, associativity = try_match_operator(source, context, false)

      # No operator found - done with this level
      break unless operator_match

      if precedence >= min_precedence
        # Calculate next minimum precedence based on associativity
        next_min = associativity == :left ? precedence + 1 : precedence

        expression_parts << operator_match
        expression_parts << climb_precedence(source, context, consume_all, next_min)
      else
        # Operator has lower precedence - backtrack and return
        source.bytepos = saved_position
        return simplify_result(expression_parts)
      end
    end

    simplify_result(expression_parts)
  end

  # Attempts to match any operator from the operator table.
  #
  # @param source [Parsanol::Source] input source
  # @param context [Parsanol::Atoms::Context] parsing context
  # @param consume_all [Boolean] consume all flag
  # @return [Array, nil] [matched_value, precedence, associativity] or nil
  def try_match_operator(source, context, consume_all)
    operators = @operator_table

    operators.each do |op_parser, prec, assoc|
      ok, value = op_parser.apply(source, context, consume_all)
      return [flatten(value, true), prec, assoc] if ok
    end

    nil
  end

  # Simplifies single-element results to avoid unnecessary nesting.
  #
  # @param result [Array] expression parts
  # @return [Object] simplified result
  def simplify_result(result)
    result.length == 1 ? result.first : result
  end

  public

  # Returns string representation for debugging
  def to_s_inner(precedence)
    op_list = @operator_table.map { |op, _, _| op.inspect }.join(', ')
    "infix_expression(#{@base_element.inspect}, [#{op_list}])"
  end
end
