# frozen_string_literal: true

# Parsanol::Parslet - Nested compatibility layer for original Parslet API
#
# This provides backwards compatibility for code that uses the original Parslet API.
# Instead of root-level Parslet constant, we use Parsanol::Parslet as a nested module.
#
# == Supported Features
#
# - All parser atoms (str, match, any, sequence, alternative, repetition, etc.)
# - Parser class with rule definitions
# - Transform for AST construction
# - Error reporting with Cause
# - Treetop-style expression parsing via exp()
#
# == Limitations
#
# - Some advanced features may require direct Parsanol usage
#
# Usage:
#   require 'parsanol/parslet'
#
#   class MyParser < Parsanol::Parslet::Parser
#     include Parsanol::Parslet
#     rule(:foo) { str('foo') }
#     root(:foo)
#   end
#
# Migration from original Parslet:
#   Before: require 'parslet'
#           class MyParser < Parslet::Parser
#           include Parslet
#
#   After:  require 'parsanol/parslet'
#           class MyParser < Parsanol::Parslet::Parser
#           include Parsanol::Parslet

require 'parsanol'

module Parsanol
  module Parslet
    # Include Parsanol to get all DSL methods (str, match, any, etc.)
    include Parsanol

    # Error class alias for compatibility
    ParseFailed = Parsanol::ParseFailed

    # Atoms namespace - aliases to Parsanol atoms
    # These are the atoms explicitly loaded by lib/parsanol/atoms.rb
    module Atoms
      Base = ::Parsanol::Atoms::Base
      Str = ::Parsanol::Atoms::Str
      Re = ::Parsanol::Atoms::Re
      Sequence = ::Parsanol::Atoms::Sequence
      Alternative = ::Parsanol::Atoms::Alternative
      Repetition = ::Parsanol::Atoms::Repetition
      Named = ::Parsanol::Atoms::Named
      Entity = ::Parsanol::Atoms::Entity
      Lookahead = ::Parsanol::Atoms::Lookahead
      Cut = ::Parsanol::Atoms::Cut
      Capture = ::Parsanol::Atoms::Capture
      Scope = ::Parsanol::Atoms::Scope
      Dynamic = ::Parsanol::Atoms::Dynamic
      Infix = ::Parsanol::Atoms::Infix
      Ignored = ::Parsanol::Atoms::Ignored
      ParseFailed = ::Parsanol::ParseFailed
    end

    # Class aliases
    Parser = ::Parsanol::Parser
    Transform = ::Parsanol::Transform
    Cause = ::Parsanol::Cause
    Slice = ::Parsanol::Slice
    Source = ::Parsanol::Source
    Pattern = ::Parsanol::Pattern
    Context = ::Parsanol::Context

    # Module functions for DSL (delegate to Parsanol)
    extend self

    def match(str = nil)
      Parsanol.match(str)
    end

    def str(str)
      Parsanol.str(str)
    end

    def any
      Parsanol.any
    end

    def scope(&block)
      Parsanol.scope(&block)
    end

    def dynamic(&block)
      Parsanol.dynamic(&block)
    end

    def infix_expression(element, *operations, &reducer)
      Parsanol.infix_expression(element, *operations, &reducer)
    end

    # Parses a treetop-style expression string and returns the corresponding atom.
    # Delegates to Parsanol.exp.
    #
    # @example
    #   # the same as str('a') >> str('b').maybe
    #   exp(%q("a" "b"?))
    #
    # @param str [String] a treetop expression
    # @return [Parsanol::Atoms::Base] the corresponding parser atom
    def exp(str)
      Parsanol.exp(str)
    end

    def sequence(symbol)
      Parsanol.sequence(symbol)
    end

    def simple(symbol)
      Parsanol.simple(symbol)
    end

    def subtree(symbol)
      Parsanol.subtree(symbol)
    end

    # Class method extensions for Parser
    module ClassMethods
      # Enable automatic rule optimization for all rules in this parser.
      # @param enable [Boolean] whether to enable optimization
      def optimize_rules!(enable = true)
        @optimize_rules = enable
      end

      # Check if rule optimization is enabled.
      # @return [Boolean]
      def optimize_rules?
        @optimize_rules = false if @optimize_rules.nil?
        @optimize_rules
      end
    end

    # Extend with class methods when included
    def self.included(base)
      base.extend(ClassMethods)
    end
  end
end
