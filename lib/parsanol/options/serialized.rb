# frozen_string_literal: true

require 'json'

# Parsanol::Serialized - Serialized Transform Mode (JSON Output)
#
# This mode provides cross-language compatibility through JSON serialization.
# - Parsing AND transformation happen in Rust for maximum performance
# - Output is a JSON string that can be deserialized to any format
# - REQUIRES native extension (will raise LoadError if not available)
#
# Usage:
#   class MyParser < Parsanol::Parser
#     include Parsanol::Serialized
#     rule(:number) { match('[0-9]').repeat(1).as(:int) }
#     root(:number)
#   end
#
#   parser = MyParser.new
#   json = parser.parse_to_json("42")  # Returns JSON string
#   # => '{"int": "42"}'
#
#   # With a deserializer class
#   result = parser.parse_to_struct("42", MyDeserializer)
#
# Performance: Faster than RubyTransform because transform happens in Rust.
# Memory: Higher than ZeroCopy due to JSON serialization overhead.

module Parsanol
  module Serialized
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Define output schema for transformation
      # This is optional but helps with type checking
      #
      # @param schema [Hash] Schema definition
      # @example
      #   output_schema(
      #     number: { type: :integer },
      #     binop: { type: :object, properties: [:left, :op, :right] }
      #   )
      def output_schema(schema = nil)
        @output_schema = schema if schema
        @output_schema ||= {}
      end
    end

    # Parse input and return JSON string
    #
    # @param input [String] The input string to parse
    # @return [String] JSON string representing the parse result
    # @raise [LoadError] If native extension not available
    # @raise [Parsanol::ParseFailed] If parsing fails
    def parse_to_json(input)
      unless Parsanol::Native.available?
        raise LoadError,
          "Serialized mode requires native extension for JSON serialization. " \
          "Run `rake compile` or use Parsanol::RubyTransform for Ruby-only parsing."
      end

      grammar_json = Parsanol::Native.serialize_grammar(root)
      Parsanol::Native.parse_to_json(grammar_json, input)
    end

    # Parse input and deserialize to a Ruby object
    #
    # @param input [String] The input string to parse
    # @param deserializer_class [Class] Class with .from_json method
    # @return [Object] Deserialized object
    # @raise [LoadError] If native extension not available
    # @raise [Parsanol::ParseFailed] If parsing fails
    def parse_to_struct(input, deserializer_class)
      json = parse_to_json(input)
      deserializer_class.from_json(json)
    end

    # Parse input and return Ruby Hash (parsed JSON)
    #
    # @param input [String] The input string to parse
    # @return [Hash, Array] Ruby object from JSON
    # @raise [LoadError] If native extension not available
    # @raise [Parsanol::ParseFailed] If parsing fails
    def parse(input, options = {})
      json = parse_to_json(input)
      JSON.parse(json)
    end

    # Alias for consistency with other modes
    alias parse_to_hash parse
  end
end
