# frozen_string_literal: true

# Parses treetop-style expression strings and converts them to Parsanol atoms.
#
# This allows specifying parser rules as strings using treetop syntax instead
# of building atoms explicitly with the DSL.
#
# == Performance Note
#
# The expression parser is implemented in pure Ruby and is NOT accelerated by
# the Rust native extension. This is intentional and acceptable because:
#
# 1. Expression parsing happens at grammar definition time (once)
# 2. Expression strings are typically short (< 100 characters)
# 3. The resulting atoms can still be used with Rust-accelerated parsing
#
# If you need maximum performance for dynamically generated parsers, consider
# building atoms directly with the DSL (str, match, any, etc.) instead.
#
# == Syntax
#
# The treetop syntax supports:
#
# - Strings: 'hello' (single quotes)
# - Character classes: [a-z], [0-9]
# - Any character: .
# - Sequence: 'a' 'b' (concatenation)
# - Alternative: 'a' / 'b'
# - Optional: 'a' ? (space before ? required)
# - Zero or more: 'a' * (space before * required)
# - One or more: 'a' + (space before + required)
# - Repetition: 'a'{1,3}
# - Grouping: ('a' / 'b')+
#
# == Example
#
#   # Using exp()
#   rule(:word) { exp("'a' 'b' ?") }
#
#   # Equivalent DSL:
#   rule(:word) { str('a') >> str('b').maybe }
#
# == Result Usage
#
# The atoms produced by exp() can be used with Rust-accelerated parsing:
#
#   atom = Parsanol.exp("'a' +")
#
#   # Ruby parsing
#   atom.parse('aaa')
#
#   # Rust-accelerated parsing (if native extension available)
#   Parsanol::Native.parse_with_grammar(atom, 'aaa')
#
module Parsanol
  class Expression
    include Parsanol

    autoload :Treetop, 'parsanol/expression/treetop'

    # Creates a parser atom from a treetop-style expression string.
    #
    # @param str [String] a treetop expression
    # @param opts [Hash] options (:type => :treetop, default)
    # @return [Parsanol::Expression] expression object (call #to_parslet for atom)
    #
    # @example
    #   expr = Parsanol::Expression.new("'a' 'b' ?")
    #   atom = expr.to_parslet
    #   atom.parse('a')  # => "a"@0
    #
    def initialize(str, opts = {}, _context = self)
      @type = opts[:type] || :treetop
      @exp = str
      @parslet = transform(parse(str))
    end

    # Transforms the parse tree into a parser atom.
    #
    # @param tree [Hash] parse tree from Treetop::Parser
    # @return [Parsanol::Atoms::Base] parser atom
    def transform(tree)
      transform = Treetop::Transform.new
      transform.apply(tree)
    rescue StandardError
      warn "Could not transform: #{tree.inspect}"
      raise
    end

    # Parses the expression string and returns a parse tree.
    #
    # @param str [String] treetop expression
    # @return [Hash] parse tree
    def parse(str)
      parser = Treetop::Parser.new
      parser.parse(str)
    end

    # Returns the parser atom for this expression.
    #
    # @return [Parsanol::Atoms::Base] parser atom
    def to_parslet
      @parslet
    end
  end
end
