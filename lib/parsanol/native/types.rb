# frozen_string_literal: true

module Parsanol
  module Native
    # Type tags used in AST serialization
    # These must match the tags used by the Rust parser
    module Types
      # AST node type tags (must match Rust parser output)
      TAG_NIL = 0x00
      TAG_BOOL = 0x01
      TAG_INT = 0x02
      TAG_FLOAT = 0x03
      TAG_STRING_REF = 0x04
      TAG_ARRAY_START = 0x05
      TAG_ARRAY_END = 0x06
      TAG_HASH_START = 0x07
      TAG_HASH_END = 0x08
      TAG_HASH_KEY = 0x09
      TAG_INLINE_STRING = 0x0A

      # Frozen string constants for transformer (avoid allocations)
      SEQUENCE_TAG = ':sequence'.freeze
      REPETITION_TAG = ':repetition'.freeze
      EMPTY_STRING = ''.freeze
      EMPTY_ARRAY = [].freeze
      EMPTY_HASH = {}.freeze
    end

    # Symbol cache to avoid repeated string-to-symbol conversions
    # This is a class variable to share across all transformations
    @@symbol_cache = {}

    # Convert string key to symbol with caching
    # @param key [String, Symbol] The key to convert
    # @return [Symbol] The symbol version of the key
    def self.cached_symbol(key)
      return key if key.is_a?(Symbol)
      @@symbol_cache[key] ||= key.to_sym
    end
  end
end
