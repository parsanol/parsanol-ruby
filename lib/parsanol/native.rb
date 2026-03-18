# frozen_string_literal: true

require 'json'
require 'digest'

require 'parsanol/native/types'
require 'parsanol/native/parser'
require 'parsanol/native/serializer'

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
        grammar_json = serialize_grammar(grammar)
        Parser.parse(grammar_json, input)
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
