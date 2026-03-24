# frozen_string_literal: true

require_relative "ast_visitor"
require_relative "optimizers/quantifier_optimizer"
require_relative "optimizers/sequence_optimizer"
require_relative "optimizers/choice_optimizer"
require_relative "optimizers/lookahead_optimizer"
require_relative "optimizers/cut_inserter"

# Grammar-level optimizations for Parslet parsers
# These optimizations transform the parser AST to reduce runtime overhead
# without changing semantics.
#
# Architecture:
# - Uses Visitor pattern for clean separation of traversal and transformation
# - Each optimizer is a separate class inheriting from ASTVisitor
# - Optimizer module provides facade methods for easy access
module Parsanol
  module Optimizer
    # Simplifies redundant quantifiers in a parslet tree
    # Example: str('a').repeat(1, 1) => str('a')
    #          str('a').repeat(0, 1).repeat(0, 1) => str('a').repeat(0, 1)
    #
    # @param parslet [Parsanol::Atoms::Base] parslet to simplify
    # @return [Parsanol::Atoms::Base] simplified parslet
    def self.simplify_quantifiers(parslet)
      Optimizers::QuantifierOptimizer.new.visit(parslet)
    end

    # Simplifies sequences by flattening and merging adjacent strings
    # Example: str('a') >> str('b') => str('ab')
    #          (str('a') >> str('b')) >> str('c') => str('abc')
    #
    # @param parslet [Parsanol::Atoms::Base] parslet to simplify
    # @return [Parsanol::Atoms::Base] simplified parslet
    def self.simplify_sequences(parslet)
      Optimizers::SequenceOptimizer.new.visit(parslet)
    end

    # Simplifies choice/alternative patterns
    # Example: (A | B) | C => A | B | C
    #          A | B | A => A | B
    #
    # @param parslet [Parsanol::Atoms::Base] parslet to simplify
    # @return [Parsanol::Atoms::Base] simplified parslet
    def self.simplify_choices(parslet)
      Optimizers::ChoiceOptimizer.new.visit(parslet)
    end

    # Simplifies lookahead patterns
    # Example: !(!x) => &x (double negation elimination)
    #
    # @param parslet [Parsanol::Atoms::Base] parslet to simplify
    # @return [Parsanol::Atoms::Base] simplified parslet
    def self.simplify_lookaheads(parslet)
      Optimizers::LookaheadOptimizer.new.visit(parslet)
    end

    # Automatically insert cut operators where safe (AC-FIRST algorithm)
    # Inserts cuts after deterministic prefixes when alternatives have disjoint FIRST sets
    # This enables O(1) space complexity by allowing aggressive cache eviction
    #
    # Example: str('if') >> x | str('while') >> y
    #       => str('if').cut >> x | str('while').cut >> y
    #
    # @param parslet [Parsanol::Atoms::Base] parslet to optimize
    # @return [Parsanol::Atoms::Base] optimized parslet with cuts inserted
    def self.insert_cuts(parslet)
      Optimizers::CutInserter.new.optimize(parslet)
    end

    # Apply all optimizations in recommended order
    # This is a convenience method that applies all optimizer passes
    #
    # @param parslet [Parsanol::Atoms::Base] parslet to optimize
    # @return [Parsanol::Atoms::Base] fully optimized parslet
    def self.optimize_all(parslet)
      result = simplify_quantifiers(parslet)
      result = simplify_sequences(result)
      result = simplify_choices(result)
      result = simplify_lookaheads(result)
      insert_cuts(result)
    end
  end
end
