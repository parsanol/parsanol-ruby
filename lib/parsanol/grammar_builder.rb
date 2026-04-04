# frozen_string_literal: true

# Parsanol::GrammarBuilder - Grammar Composition
#
# Build complex grammars by importing and composing smaller grammars.
# This enables reusable grammar modules.
#
# Usage:
#   # Define reusable grammars
#   expression_grammar = GrammarBuilder.new
#     .rule("expr", str("a") | str("b"))
#     .build
#
#   type_grammar = GrammarBuilder.new
#     .rule("type", str("int") | str("str"))
#     .build
#
#   # Compose into a new grammar
#   combined = GrammarBuilder.new
#     .import(expression_grammar, prefix: "expr")
#     .import(type_grammar, prefix: "type")
#     .rule("typed", seq([ref("expr:root"), str(":"), ref("type:root")]))
#     .build
#
# Requires native extension for full functionality.

module Parsanol
  class GrammarBuilder
    # Create a new grammar builder
    def initialize
      @rules = {}
      @imports = []
      @root = nil
    end

    # Define a rule
    #
    # @param name [String, Symbol] Rule name
    # @param parslet [Parsanol::Atoms::Base] Parslet atom
    # @return [self] For chaining
    def rule(name, parslet)
      @rules[name.to_s] = parslet
      self
    end

    # Get a rule for modification
    #
    # @param name [String, Symbol] Rule name
    # @return [Parsanol::Atoms::Base, nil] The rule atom
    def [](name)
      @rules[name.to_s]
    end

    # Set the root rule
    #
    # @param name [String, Symbol] Root rule name
    # @return [self] For chaining
    def root(name)
      @root = name.to_s
      self
    end

    # Import another grammar with optional prefix
    #
    # @param grammar [GrammarBuilder, Hash] Grammar to import
    # @param prefix [String, nil] Optional prefix for imported rules
    # @return [self] For chaining
    def import(grammar, prefix: nil)
      grammar_data = case grammar
                     when GrammarBuilder
                       grammar.to_h
                     when Hash
                       grammar
                     else
                       raise ArgumentError,
                             "Expected GrammarBuilder or Hash, got #{grammar.class}"
                     end

      @imports << { grammar: grammar_data, prefix: prefix }
      self
    end

    # Import with explicit rule mapping
    #
    # @param grammar [GrammarBuilder, Hash] Grammar to import
    # @param prefix [String, nil] Optional prefix
    # @param rules [Hash] Rule mapping {from_rule: to_rule}
    # @return [self] For chaining
    def import_with_rules(grammar, prefix: nil, rules: {})
      grammar_data = case grammar
                     when GrammarBuilder
                       grammar.to_h
                     when Hash
                       grammar
                     else
                       raise ArgumentError,
                             "Expected GrammarBuilder or Hash, got #{grammar.class}"
                     end

      @imports << { grammar: grammar_data, prefix: prefix, rules: rules }
      self
    end

    # Build the grammar
    #
    # @return [Hash] Grammar representation
    def build
      {
        rules: @rules,
        root: @root,
        imports: @imports,
      }
    end

    # Convert to JSON for native parser
    #
    # @return [String] JSON representation
    def to_json(*)
      build.to_json
    end

    # Get as a Hash
    #
    # @return [Hash] Grammar representation
    def to_h
      build
    end

    # Reference another rule in this grammar
    #
    # @param name [String, Symbol] Rule name
    # @return [Parsanol::Atoms::Entity] Entity referencing the rule
    def ref(name)
      Parsanol::Atoms::Entity.new(name)
    end

    # Reference the root of another grammar
    #
    # @param grammar_name [String] Name of the grammar (for prefixed imports)
    # @return [Parsanol::Atoms::Entity] Entity referencing the root
    def ref_root(grammar_name = nil)
      if grammar_name
        ref("#{grammar_name}:root")
      else
        ref("root")
      end
    end

    class << self
      # Create a grammar from a block
      #
      # @yield [GrammarBuilder] Builder to configure
      # @return [Hash] Built grammar
      def build(&)
        builder = new
        builder.instance_eval(&)
        builder.build
      end

      # Import a grammar from JSON string
      #
      # @param json [String] JSON representation
      # @return [Hash] Grammar representation
      def from_json(json)
        JSON.parse(json)
      end
    end
  end

  # Module methods for DSL
  module GrammarBuilderDSL
    # Create a new grammar builder
    #
    # @return [GrammarBuilder] New builder
    def grammar(&)
      GrammarBuilder.build(&)
    end
  end
end
