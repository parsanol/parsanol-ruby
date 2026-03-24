# frozen_string_literal: true

require_relative "../ast_visitor"

module Parsanol
  module Optimizers
    # Optimizes alternative/choice patterns in the AST
    # Follows visitor pattern for clean separation of concerns
    #
    # Transformations:
    # - (A | B) | C => A | B | C (flatten nested alternatives)
    # - A | B | A => A | B (remove duplicates)
    # - Alternative(A) => A (unwrap single-element alternatives)
    class ChoiceOptimizer < ASTVisitor
      # Visit an alternative node and apply choice optimizations
      # @param parslet [Parsanol::Atoms::Alternative] alternative to optimize
      # @return [Parsanol::Atoms::Base] optimized parslet
      def visit_alternative(parslet)
        # First optimize children recursively
        new_alternatives = parslet.alternatives.map { |p| visit(p) }

        # Optimization 1: Flatten nested alternatives
        flattened = flatten_alternatives(new_alternatives)

        # Optimization 2: Remove duplicate alternatives
        deduplicated = deduplicate_alternatives(flattened)

        # Optimization 3: Unwrap single-element alternatives
        return deduplicated[0] if deduplicated.size == 1

        # Return optimized alternative if changed
        if deduplicated == parslet.alternatives
          parslet
        else
          Parsanol::Atoms::Alternative.new(*deduplicated)
        end
      end

      private

      # Flatten nested alternatives into a single level
      # @param alternatives [Array<Parsanol::Atoms::Base>] array of alternatives
      # @return [Array<Parsanol::Atoms::Base>] flattened array
      def flatten_alternatives(alternatives)
        result = []
        alternatives.each do |alt|
          if alt.is_a?(Parsanol::Atoms::Alternative)
            result.concat(alt.alternatives)
          else
            result << alt
          end
        end
        result
      end

      # Remove duplicate alternatives using structural equality
      # @param alternatives [Array<Parsanol::Atoms::Base>] array of alternatives
      # @return [Array<Parsanol::Atoms::Base>] deduplicated array
      def deduplicate_alternatives(alternatives)
        return alternatives if alternatives.size < 2

        # Use to_s as proxy for structural equality
        seen = {}
        result = []

        alternatives.each do |alt|
          key = alt.to_s
          unless seen[key]
            seen[key] = true
            result << alt
          end
        end

        result
      end
    end
  end
end
