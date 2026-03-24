# frozen_string_literal: true

require_relative "../ast_visitor"

module Parsanol
  module Optimizers
    # Optimizes lookahead patterns in the AST
    # Follows visitor pattern for clean separation of concerns
    #
    # Transformations:
    # - !(!x) => &x (double negation elimination)
    # - &(&x) => &x (positive lookahead is idempotent)
    # - !(&x) => !x (negative of positive)
    # - &(!x) => !x (positive of negative)
    class LookaheadOptimizer < ASTVisitor
      # Visit a lookahead node and apply lookahead optimizations
      # @param parslet [Parsanol::Atoms::Lookahead] lookahead to optimize
      # @return [Parsanol::Atoms::Base] optimized parslet
      def visit_lookahead(parslet)
        # First optimize the child
        inner = visit(parslet.bound_parslet)

        # If inner is also a lookahead, simplify nested lookaheads
        if inner.is_a?(Parsanol::Atoms::Lookahead)
          outer_positive = parslet.positive
          inner_positive = inner.positive

          # !(!x) => &x (double negation)
          if !outer_positive && !inner_positive
            return Parsanol::Atoms::Lookahead.new(inner.bound_parslet,
                                                  true)
          end

          # &(&x) => &x (idempotent)
          return inner if outer_positive && inner_positive

          # !(&x) => !x (negative of positive)
          if !outer_positive && inner_positive
            return Parsanol::Atoms::Lookahead.new(inner.bound_parslet,
                                                  false)
          end

          # &(!x) => !x (positive of negative)
          return inner if outer_positive && !inner_positive
        end

        # Return lookahead with optimized child
        if inner.equal?(parslet.bound_parslet)
          parslet
        else
          Parsanol::Atoms::Lookahead.new(inner, parslet.positive)
        end
      end
    end
  end
end
