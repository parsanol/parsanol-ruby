# frozen_string_literal: true

# Parsanol - A high-performance PEG parser construction library for Ruby.
#
# Typical usage:
#
#   require 'parsanol'
#
#   class MyParser < Parsanol::Parser
#     rule(:a) { str('a').repeat }
#     root(:a)
#   end
#
#   result = MyParser.new.parse('aaaa')   # => 'aaaa'@0
#
# Parsanol provides a declarative DSL for constructing parsers using PEG
# (Parsing Expression Grammar) semantics. The library is designed as a
# high-performance, feature-rich alternative to Parslet.
#
# == Two-Stage Parsing
#
# Parsing is typically done in two stages:
#
# 1. Parse the input string to produce an intermediate tree
# 2. Transform the tree into an application-specific AST
#
# This separation allows grammar changes without affecting downstream code.
#
# == Error Handling
#
# Failed parses raise {Parsanol::ParseFailed} with detailed error information:
#
#   begin
#     parser.parse(invalid_input)
#   rescue Parsanol::ParseFailed => e
#     puts e.parse_failure_cause.ascii_tree
#   end
#
# Inspired by Parslet (MIT License).

module Parsanol
  # Hook to extend including classes with ClassMethods.
  def self.included(base)
    base.extend(ClassMethods)
  end

  # Exception raised when parsing fails. Contains detailed error information
  # in the #parse_failure_cause attribute.
  class ParseFailed < StandardError
    def initialize(message, cause = nil)
      super(message)
      @parse_failure_cause = cause
    end

    # Detailed cause of the parse failure.
    # @return [Parsanol::Cause]
    attr_reader :parse_failure_cause
  end

  # Class methods added to classes that include Parsanol.
  module ClassMethods
    # Enable automatic rule optimization for all rules in this parser.
    # Optimizations include quantifier simplification, sequence flattening,
    # choice reordering, and lookahead simplification.
    #
    # NOTE: Optimizations are DISABLED BY DEFAULT as of v3.1.0.
    # Use this method to opt-in for complex grammars.
    def optimize_rules!(enable = true)
      @optimize_rules = enable
    end

    # Disable automatic rule optimization.
    def disable_optimization!
      @optimize_rules = false
    end

    # Check if rule optimization is enabled.
    # @return [Boolean]
    def optimize_rules?
      @optimize_rules = false if @optimize_rules.nil?
      @optimize_rules
    end

    # Define a named grammar rule. Creates a method that returns an Entity atom.
    # Rules are memoized for efficiency.
    #
    # @param name [Symbol] the rule name
    # @param opts [Hash] options (:label for custom labeling)
    # @yield block that returns the rule's parser atom
    def rule(name, opts = {}, &definition)
      undef_method name if method_defined? name
      define_method(name) do
        @rule_cache ||= {}
        return @rule_cache[name] if @rule_cache.key?(name)

        wrapper = proc {
          atom = instance_eval(&definition)

          if self.class.optimize_rules?
            atom = Parsanol::Optimizer.simplify_quantifiers(atom)
            atom = Parsanol::Optimizer.simplify_sequences(atom)
            atom = Parsanol::Optimizer.simplify_choices(atom)
            atom = Parsanol::Optimizer.simplify_lookaheads(atom)
          end

          atom
        }

        @rule_cache[name] = Atoms::Entity.new(name, opts[:label], &wrapper)
      end
    end
  end

  # Helper class for bracket notation character class matching.
  # @api private
  class CharacterClassBuilder
    def [](chars)
      Atoms::Re.new("[#{chars}]")
    end
  end

  # Creates a character class matcher. Supports both method and bracket forms.
  #
  # @overload match(pattern)
  #   @param pattern [String] regex character class
  # @overload match[]
  #   @return [CharacterClassBuilder] builder for bracket notation
  # @return [Parsanol::Atoms::Re] regex atom
  def match(pattern = nil)
    return CharacterClassBuilder.new unless pattern

    Atoms::Re.new(pattern)
  end
  module_function :match

  # Creates a literal string matcher.
  #
  # @param literal [String] the string to match
  # @return [Parsanol::Atoms::Str] string atom
  def str(literal)
    Atoms::Str.new(literal)
  end
  module_function :str

  # Creates a matcher for any single character.
  #
  # @return [Parsanol::Atoms::Re] regex atom matching '.'
  def any
    Atoms::Re.new(".")
  end
  module_function :any

  # Creates a new variable scope for captures. Inner captures shadow outer
  # ones with the same name during the block's execution.
  #
  # @yield block containing scoped parsing
  # @return [Parsanol::Atoms::Scope] scope atom
  def scope(&block)
    Atoms::Scope.new(block)
  end
  module_function :scope

  # Creates a dynamic parser that is evaluated at parse time.
  # Useful for context-dependent parsing. Use sparingly due to performance.
  #
  # @yield block returning a parser atom or parse result
  # @return [Parsanol::Atoms::Dynamic] dynamic atom
  def dynamic(&block)
    Atoms::Dynamic.new(block)
  end
  module_function :dynamic

  # Creates an infix expression parser with operator precedence.
  # Operators are specified as [atom, precedence, associativity] tuples.
  #
  # @param operand [Parsanol::Atoms::Base] parser for operands
  # @param operators [Array<Array>] operator definitions
  # @yield optional block to customize result tree structure
  # @return [Parsanol::Atoms::Infix] infix parser
  def infix_expression(operand, *operators, &)
    Atoms::Infix.new(operand, operators, &)
  end
  module_function :infix_expression

  # Creates a pattern binding for sequence matching in transforms.
  # Only matches array values, not single elements.
  #
  # @param name [Symbol] binding variable name
  # @return [Parsanol::Pattern::SequenceBind] sequence pattern
  def sequence(name)
    Pattern::SequenceBind.new(name)
  end
  module_function :sequence

  # Creates a pattern binding for simple (leaf) value matching.
  # Matches anything that is not a Hash or Array.
  #
  # @param name [Symbol] binding variable name
  # @return [Parsanol::Pattern::SimpleBind] simple pattern
  def simple(name)
    Pattern::SimpleBind.new(name)
  end
  module_function :simple

  # Creates a pattern binding that matches any subtree.
  # This is the most permissive pattern type.
  #
  # @param name [Symbol] binding variable name
  # @return [Parsanol::Pattern::SubtreeBind] subtree pattern
  def subtree(name)
    Pattern::SubtreeBind.new(name)
  end
  module_function :subtree

  # Parses a treetop-style expression string and returns the corresponding atom.
  #
  # This is a convenience method for defining parsers using treetop syntax.
  # The expression parser is pure Ruby (not Rust-accelerated) since it runs only
  # at grammar definition time. The resulting atoms can be used with native parsing.
  #
  # @note Whitespace is required before operators: 'a' ? not 'a'?
  #
  # @example Basic usage
  #   exp("'a' 'b' ?")  # => str('a') >> str('b').maybe
  #
  # @example With Rust-accelerated parsing
  #   atom = exp("'a' +")
  #   Native.parse_with_grammar(atom, 'aaa')  # Uses Rust extension
  #
  # @param str [String] a treetop expression string
  # @return [Parsanol::Atoms::Base] the corresponding parser atom
  # @see Parsanol::Expression for full syntax documentation
  def exp(str)
    Expression.new(str).to_parslet
  end
  module_function :exp

  autoload :Expression, "parsanol/expression"
end

require "parsanol/version"
require "parsanol/resettable"
require "parsanol/result"
require "parsanol/slice"
require "parsanol/string_view"
require "parsanol/rope"
require "parsanol/pool"
require "parsanol/pools/slice_pool"
require "parsanol/pools/array_pool"
require "parsanol/pools/position_pool"
require "parsanol/buffer"
require "parsanol/pools/buffer_pool"
require "parsanol/lazy_result"
require "parsanol/result_builder"
require "parsanol/first_set"
require "parsanol/cause"
require "parsanol/source"
require "parsanol/atoms"
require "parsanol/pattern"
require "parsanol/pattern/binding"
require "parsanol/transform"
require "parsanol/parser"
require "parsanol/error_reporter"
require "parsanol/scope"
require "parsanol/optimizer"
require "parsanol/options"
require "parsanol/native"

# New features (require native extension for full functionality)
require "parsanol/source_location"
require "parsanol/grammar_builder"
require "parsanol/streaming_parser"
require "parsanol/incremental_parser"
require "parsanol/builder_callbacks"
require "parsanol/parallel"

# Add GrammarBuilder DSL to Parsanol module
Parsanol.extend(Parsanol::GrammarBuilderDSL)
