# frozen_string_literal: true

# Parsanol::RubyTransform - Ruby Transform Mode (Parslet-Compatible)
#
# This is the default parsing mode that provides maximum flexibility.
# - Parsing can use Rust (if available) or pure Ruby
# - Transformation happens in Ruby using Parslet-style Transform class
#
# Usage:
#   class MyParser < Parsanol::Parser
#     include Parsanol::RubyTransform
#     rule(:number) { match('[0-9]').repeat(1).as(:int) }
#     root(:number)
#   end
#
#   parser = MyParser.new
#   tree = parser.parse("42")  # Returns generic tree
#   ast = transform.apply(tree)  # Transform in Ruby
#
# To use Rust backend for parsing:
#   class MyParser < Parsanol::Parser
#     include Parsanol::RubyTransform
#     parse_backend :rust  # Will raise if native extension not available
#     ...
#   end

module Parsanol
  module RubyTransform
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # Get or set the parsing backend
      # @param backend [Symbol] :ruby (default) or :rust
      # @return [Symbol] Current backend setting
      def parse_backend(backend = nil)
        @parse_backend = backend if backend
        @parse_backend ||= :ruby
      end

      # Setter for parsing backend
      # @param backend [Symbol] :ruby or :rust
      def parse_backend=(backend)
        @parse_backend = backend
      end

      # Configure parsing to use Rust backend
      # Raises LoadError if native extension not available
      def use_rust_backend!
        unless Parsanol::Native.available?
          raise LoadError,
                "Rust backend requested but native extension not available. " \
                "Run `rake compile` to build the extension."
        end
        @parse_backend = :rust
      end

      # Configure parsing to use pure Ruby (default)
      def use_ruby_backend!
        @parse_backend = :ruby
      end
    end

    # Parse input and return generic tree
    #
    # @param input [String] The input string to parse
    # @param options [Hash] Parse options
    # @option options [Boolean] :consume_all (true) Consume entire input
    # @return [Hash, Array, String, Parsanol::Slice] Parse tree
    # @raise [Parsanol::ParseFailed] If parsing fails
    def parse(input, options = {})
      if self.class.parse_backend == :rust && Parsanol::Native.available?
        parse_with_rust(input, options)
      else
        parse_with_ruby(input, options)
      end
    end

    # Parse and apply transform in one step
    #
    # @param input [String] The input string to parse
    # @param transform [Parsanol::Transform] Transform to apply
    # @param options [Hash] Parse options
    # @return [Object] Transformed result
    def parse_with_transform(input, transform, options = {})
      tree = parse(input, options)
      transform.apply(tree)
    end

    private

    # Parse using Rust native extension
    def parse_with_rust(input, options = {})
      options.fetch(:consume_all, true)

      # Use native parser with Parslet-compatible output
      Parsanol::Native.parse_parslet_compatible(root, input)
    end

    # Parse using pure Ruby
    def parse_with_ruby(input, options = {})
      # Call the root parslet's parse method directly
      root.parse(input, options)
    end
  end
end
