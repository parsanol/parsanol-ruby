# frozen_string_literal: true

# Parsanol::ZeroCopy - Zero-Copy Transform Mode (Direct FFI Object Construction)
#
# This mode provides MAXIMUM PERFORMANCE through zero-copy FFI.
# - Rust directly constructs Ruby objects via rb_class_new, rb_ivar_set
# - No serialization overhead whatsoever
# - REQUIRES native extension AND type mapping definitions
#
# Usage:
#   # Define Ruby classes that mirror Rust types
#   module Calculator
#     class Number < Expr
#       attr_reader :value
#       def initialize(value); @value = value; end
#       def eval = @value
#     end
#
#     class BinOp < Expr
#       attr_reader :left, :op, :right
#       def eval; ...; end
#     end
#   end
#
#   class CalculatorParser < Parsanol::Parser
#     include Parsanol::ZeroCopy
#
#     rule(:number) { ... }
#     root(:expression)
#
#     # Type mapping (tells Rust which Ruby classes to construct)
#     output_types(
#       number: Calculator::Number,
#       binop: Calculator::BinOp
#     )
#   end
#
#   parser = CalculatorParser.new
#   expr = parser.parse("42+8")  # Returns Calculator::Number or BinOp DIRECTLY
#   puts expr.eval  # No transform needed!
#
# Performance: FASTEST mode (18-44x faster than pure Ruby)
# Memory: Lowest overhead (zero-copy, no serialization)

module Parsanol
  module ZeroCopy
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Define output type mapping for zero-copy construction
      #
      # This tells the Rust parser which Ruby classes to instantiate
      # for each named capture in the grammar.
      #
      # @param types [Hash] Mapping of rule names to Ruby classes
      # @example
      #   output_types(
      #     number: Calculator::Number,
      #     binop: Calculator::BinOp,
      #     expr: Calculator::Expr
      #   )
      def output_types(types = nil)
        @output_types = types if types
        @output_types ||= {}
      end

      # Define a single output type mapping
      #
      # @param rule_name [Symbol, String] Name of the rule
      # @param ruby_class [Class] Ruby class to instantiate
      # @example
      #   output_type :number, Calculator::Number
      def output_type(rule_name, ruby_class)
        output_types[rule_name.to_sym] = ruby_class
      end

      # Get output types as a hash suitable for FFI
      #
      # @return [Hash] String keys, class names as values
      def output_types_for_ffi
        output_types.transform_keys(&:to_s).transform_values do |klass|
          klass.is_a?(Class) ? klass.name : klass.to_s
        end
      end
    end

    # Parse input and return direct Ruby objects (no serialization)
    #
    # @param input [String] The input string to parse
    # @param options [Hash] Parse options (ignored for zero-copy)
    # @return [Object] Direct Ruby object (type depends on grammar)
    # @raise [LoadError] If native extension not available
    # @raise [Parsanol::ParseFailed] If parsing fails
    def parse(input, _options = {})
      unless Parsanol::Native.available?
        raise LoadError,
              "ZeroCopy mode requires native extension for direct FFI object construction. " \
              "Run `rake compile` to build the extension, or use " \
              "Parsanol::RubyTransform for Ruby-only parsing."
      end

      grammar_json = Parsanol::Native.serialize_grammar(root)
      type_map = self.class.output_types_for_ffi

      if type_map.empty?
        raise ArgumentError,
              "ZeroCopy mode requires output_types to be defined. " \
              "Add `output_types(number: MyNumberClass)` to your parser class."
      end

      Parsanol::Native.parse_to_objects(grammar_json, input, type_map)
    end

    # Parse with explicit type map override
    #
    # @param input [String] The input string to parse
    # @param type_map [Hash] Override type mapping for this parse
    # @return [Object] Direct Ruby object
    def parse_with_types(input, type_map)
      raise LoadError, 'ZeroCopy mode requires native extension.' unless Parsanol::Native.available?

      grammar_json = Parsanol::Native.serialize_grammar(root)
      Parsanol::Native.parse_to_objects(grammar_json, input, type_map)
    end
  end
end
