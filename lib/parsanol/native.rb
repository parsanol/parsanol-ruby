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
      # The transformation happens in pure Ruby after batch decoding to avoid FFI overhead.
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

        # Use batch format for maximum performance
        # 1. Rust parses and returns flat u64 array (minimal FFI overhead)
        # 2. Ruby decodes batch format (pure Ruby, no FFI)
        # 3. Ruby joins consecutive slices (pure Ruby, no FFI)
        # 4. Ruby applies flatten transformation (pure Ruby, no FFI)
        slice_class = Parsanol::Slice
        batch_data = _parse_batch_raw(grammar_json, input)

        BatchDecoder.decode_and_flatten(batch_data, input, slice_class, grammar_atom)
      end

      # Fast batch parsing - uses u64 array format to minimize FFI overhead.
      #
      # This is 3-5x faster than regular parse() for large grammars.
      # The batch format passes a flat u64 array across FFI, then decodes
      # in pure Ruby, avoiding expensive per-node FFI calls.
      #
      # @param grammar_json [String] Pre-serialized grammar JSON
      # @param input [String] Input string to parse
      # @param slice_class [Class] The Slice class to use for string refs
      # @return [Hash, Array, Slice] Raw AST (not flattened)
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
