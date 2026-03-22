# frozen_string_literal: true

require 'json'
require 'digest'

require 'parsanol/native/types'
require 'parsanol/native/parser'
require 'parsanol/native/serializer'
require 'parsanol/native/batch_decoder'

module Parsanol
  module Native
    VERSION = '0.1.0'

    class << self
      # Check if native extension is available
      def available?
        Parser.available?
      end

      # Parse input with a Ruby grammar, returning clean AST with lazy line/column.
      #
      # Uses batch FFI format for maximum performance (3-5x faster than object-by-object).
      # The Rust-side transformation (to_parslet_compatible) produces Parslet-compatible
      # output that can be consumed directly by Builder.build without additional
      # Ruby-side transformation.
      #
      # @param grammar [Parsanol::Atoms::Base] Ruby grammar definition
      # @param input [String] Input string to parse
      # @return [Hash, Array, Parsanol::Slice] Transformed AST
      #
      # @example Simple parsing
      #   result = Parsanol::Native.parse(str('hello').as(:greeting), 'hello')
      #   # => {greeting: "hello"@0}
      #
      # @example With lazy line/column
      #   result = Parsanol::Native.parse(str('hello').as(:greeting), "hello\nworld")
      #   result[:greeting].line_and_column  # => [1, 1]
      #
      def parse(grammar, input)
        raise LoadError, "Native parser not available" unless available?

        # Handle both grammar atoms and pre-serialized JSON strings
        if grammar.is_a?(String)
          grammar_json = grammar
          grammar_atom = nil
        else
          grammar_json = Parser.serialize_grammar(grammar)
          grammar_atom = grammar
        end

        # Use _parse_raw which returns properly tagged Ruby arrays via transform_ast.
        # The batch format doesn't preserve :repetition/:sequence tags, so we use
        # the direct FFI path. Apply the Ruby transformer to handle tags correctly.
        raw_ast = _parse_raw(grammar_json, input)
        BatchDecoder.decode_and_flatten(raw_ast, input, Parsanol::Slice, grammar_atom)
      end

      # Parse and return RAW AST without transformation.
      #
      # This returns the raw Parslet intermediate format before any transformation.
      # Use this only if you need the raw AST for custom processing.
      #
      # For most use cases (including Expressir), use parse() instead which
      # returns properly transformed AST.
      #
      # @param grammar [Parsanol::Atoms::Base] Ruby grammar definition
      # @param input [String] Input string to parse
      # @return [Hash, Array] Raw untransformed AST
      #
      # @example Raw parsing
      #   result = Parsanol::Native.parse_raw(str('hello').as(:greeting), 'hello')
      #   # => {:syntax => [{:spaces => ...}, {:greeting => "hello"@0}, {:spaces => ...}]}
      #
      def parse_raw(grammar, input)
        raise LoadError, "Native parser not available" unless available?

        # Handle both grammar atoms and pre-serialized JSON strings
        if grammar.is_a?(String)
          grammar_json = grammar
        else
          grammar_json = Parser.serialize_grammar(grammar)
        end

        # Use batch_raw format for raw AST (no transformation)
        slice_class = Parsanol::Slice
        batch_data = _parse_batch_raw(grammar_json, input)

        # Decode without transformation - raw AST format
        BatchDecoder.decode(batch_data, input, slice_class)
      end

      # Fast batch parsing - uses u64 array format to minimize FFI overhead.
      #
      # This is 3-5x faster than regular parse() for large grammars.
      # The batch format passes a flat u64 array across FFI, then decodes
      # in pure Ruby, avoiding expensive per-node FFI calls.
      #
      # Returns RAW AST without transformation. For Expressir use case,
      # use parse() instead which returns properly transformed AST.
      #
      # @param grammar_json [String] Pre-serialized grammar JSON
      # @param input [String] Input string to parse
      # @param slice_class [Class] The Slice class to use for string refs
      # @return [Hash, Array, Slice] Raw AST (not transformed)
      def parse_batch(grammar_json, input, slice_class)
        raise LoadError, "Native parser not available" unless available?

        # Call native extension's _parse_batch_raw method (named with _raw suffix
        # to avoid conflict with this Ruby wrapper method)
        batch_data = _parse_batch_raw(grammar_json, input)
        BatchDecoder.decode(batch_data, input, slice_class)
      end

      # Get the Slice class
      private def get_slice_class
        Parsanol::Slice
      end

      # Serialize a Ruby grammar to JSON (cached).
      #
      # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
      # @return [String] JSON string
      def serialize_grammar(root_atom)
        Parser.serialize_grammar(root_atom)
      end

      # Clear grammar caches (call if grammar changes)
      def clear_cache
        Parser.clear_cache
      end

      # Get cache statistics
      def cache_stats
        Parser.cache_stats
      end
    end
  end
end

# Attempt to load native extension
begin
  ruby_version = RUBY_VERSION.split('.').take(2).join('.')
  require "parsanol/#{ruby_version}/parsanol_native"
rescue LoadError
  begin
    require 'parsanol/parsanol_native'
  rescue LoadError
    # Native extension not built yet
  end
end
