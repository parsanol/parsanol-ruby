# frozen_string_literal: true

require 'parsanol/native'

module Parsanol
  # Generic lexer for fast tokenization
  #
  # Create a lexer by subclassing and defining tokens:
  #
  #   class JsonLexer < Parsanol::Lexer
  #     token :string, /"[^"]*"/
  #     token :number, /-?[0-9]+(\.[0-9]+)?/
  #     token :true, /true/
  #     token :false, /false/
  #     token :null, /null/
  #     token :lbrace, /\{/
  #     token :rbrace, /\}/
  #     token :lbracket, /\[/
  #     token :rbracket, /\]/
  #     token :colon, /:/
  #     token :comma, /,/
  #
  #     ignore /\s+/
  #   end
  #
  #   lexer = JsonLexer.new
  #   tokens = lexer.tokenize('{"name": "test"}')
  #
  class Lexer
    class << self
      # Define a token pattern
      #
      # @param name [Symbol] Token type name
      # @param pattern [Regexp] Pattern to match
      # @param priority [Integer] Priority for conflict resolution (higher = preferred)
      # @param block [Proc] Optional block to transform the matched value
      def token(name, pattern, priority: 0, &block)
        token_definitions << Definition.new(
          name: name.to_s,
          pattern: pattern.source,
          priority: priority,
          ignore: false,
          transform: block
        )
      end

      # Define patterns to ignore (e.g., whitespace, comments)
      #
      # @param pattern [Regexp] Pattern to ignore
      def ignore(pattern)
        token_definitions << Definition.new(
          name: '__ignore__',
          pattern: pattern.source,
          priority: 0,
          ignore: true,
          transform: nil
        )
      end

      # Define keywords (identifiers with higher priority)
      #
      # @param keywords [Array<Symbol>] Keyword names
      # @param priority [Integer] Priority (default: 100)
      def keyword(*keywords, priority: 100)
        keywords.each do |kw|
          token_definitions << Definition.new(
            name: kw.to_s.upcase,
            pattern: Regexp.new(Regexp.escape(kw.to_s), Regexp::IGNORECASE).source,
            priority: priority,
            ignore: false,
            transform: nil
          )
        end
      end

      # Get token definitions for this lexer class
      #
      # @return [Array<Definition>] Token definitions
      def token_definitions
        @token_definitions ||= []
      end

      # Inherit token definitions from parent class
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@token_definitions, token_definitions.dup)
      end
    end

    # Token definition
    Definition = Struct.new(:name, :pattern, :priority, :ignore, :transform)

    # Initialize the lexer
    def initialize
      @lexer_id = nil
      @transforms = build_transforms
    end

    # Tokenize input string
    #
    # @param input [String] Input to tokenize
    # @return [Array<Hash>] Array of tokens with type, value, and location
    def tokenize(input)
      ensure_lexer_created

      tokens = Native.tokenize_with_lexer(@lexer_id, input)

      # Apply any transforms
      tokens.map do |token|
        transform = @transforms[token['type']]
        if transform
          token = token.dup
          token['value'] = transform.call(token['value'])
        end
        token
      end
    end

    private

    def ensure_lexer_created
      return if @lexer_id

      definitions = self.class.token_definitions.map do |d|
        {
          'name' => d.name,
          'pattern' => d.pattern,
          'priority' => d.priority,
          'ignore' => d.ignore
        }
      end

      @lexer_id = Native.create_lexer(definitions)
    end

    def build_transforms
      transforms = {}
      self.class.token_definitions.each do |d|
        transforms[d.name] = d.transform if d.transform && !d.ignore
      end
      transforms
    end
  end
end
