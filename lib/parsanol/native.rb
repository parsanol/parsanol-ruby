# frozen_string_literal: true

require 'json'
require 'digest'

# Entry point for native parsing functionality
require 'parsanol/native/types'
require 'parsanol/native/parser'
require 'parsanol/native/serializer'

module Parsanol
  module Native
    VERSION = '0.1.0'

    class << self
      # =========================================================================
      # PUBLIC API
      # =========================================================================

      # Check if native extension is available
      def available?
        Parser.available?
      end

      # Parse input and return a clean, normalized AST with lazy line/column support
      #
      # This is the MAIN parsing method. It returns a clean AST with:
      # - Symbol keys instead of string keys
      # - Joined character sequences (not character arrays)
      # - No empty spaces arrays
      # - Slice objects with lazy line/column computation
      #
      # Line/column is computed lazily only when Slice#line_and_column is called,
      # providing zero overhead for users who don't need position info.
      #
      # @param grammar_json [String] JSON-serialized grammar
      # @param input [String] Input string to parse
      # @return [Hash, Array, Parsanol::Slice] Transformed AST
      #
      # @example Basic usage
      #   grammar = str('hello').as(:greeting)
      #   grammar_json = Parsanol::Native.serialize_grammar(grammar)
      #   result = Parsanol::Native.parse(grammar_json, 'hello')
      #   # => {greeting: "hello"@0}
      #
      # @example With line/column (computed lazily)
      #   result = Parsanol::Native.parse(grammar_json, "hello\nworld")
      #   slice = result[:greeting]
      #   slice.line_and_column  # => [1, 1]
      #
      # @note Provides up to 26x speedup over pure Ruby parsing.
      def parse(grammar_json, input)
        Parser.parse(grammar_json, input)
      end

      # Serialize a grammar to JSON for use with parse()
      #
      # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
      # @return [String] JSON string
      def serialize_grammar(root_atom)
        Parser.serialize_grammar(root_atom)
      end

      # Parse with automatic grammar serialization
      #
      # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
      # @param input [String] Input string to parse
      # @return [Object] Transformed AST
      def parse_with_grammar(root_atom, input)
        grammar_json = serialize_grammar(root_atom)
        parse(grammar_json, input)
      end

      # Clear grammar caches (call if grammar changes)
      def clear_cache
        Parser.clear_cache
      end

      # Get cache statistics
      def cache_stats
        Parser.cache_stats
      end

      # =========================================================================
      # LOW-LEVEL API
      # =========================================================================

      # Parse using batch mode (returns flat u64 array)
      # @api private
      def parse_batch(grammar_json, input)
        Parser.parse_batch(grammar_json, input)
      end

      # Parse with streaming builder callback
      # @api private
      def parse_with_builder(grammar_json, input, builder)
        Parser.parse_with_builder(grammar_json, input, builder)
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
