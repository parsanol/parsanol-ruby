# frozen_string_literal: true

require_relative '../ast_visitor'

module Parsanol
  module Optimizers
    # Optimizes repetition/quantifier patterns in the AST
    # Follows visitor pattern for clean separation of concerns
    #
    # Transformations:
    # - repeat(1,1) => unwrap (identity transformation)
    # - repeat(0,1).repeat(0,1) => repeat(0,1) (idempotent)
    # - repeat(n,n).repeat(m,m) => repeat(n*m,n*m) (multiply exact counts)
    class QuantifierOptimizer < ASTVisitor
      # Visit a repetition node and apply quantifier optimizations
      # @param parslet [Parsanol::Atoms::Repetition] repetition to optimize
      # @return [Parsanol::Atoms::Base] optimized parslet
      def visit_repetition(parslet)
        # First optimize the child
        inner = visit(parslet.parslet)

        # Optimization 1: repeat(1,1) is identity - unwrap it
        if parslet.min == 1 && parslet.max == 1
          return inner
        end

        # Optimization 2: Nested repetitions
        if inner.is_a?(Parsanol::Atoms::Repetition)
          # repeat(0,1).repeat(0,1) => repeat(0,1) (idempotent)
          if parslet.min == 0 && parslet.max == 1 &&
             inner.min == 0 && inner.max == 1
            return inner
          end

          # repeat(n,n).repeat(m,m) => repeat(n*m,n*m) for exact counts
          if parslet.min == parslet.max && inner.min == inner.max &&
             parslet.max && inner.max
            new_count = parslet.min * inner.min
            return Parsanol::Atoms::Repetition.new(
              inner.parslet,
              new_count,
              new_count,
              parslet.result_tag
            )
          end
        end

        # Return optimized repetition with simplified child
        if inner.equal?(parslet.parslet)
          parslet
        else
          Parsanol::Atoms::Repetition.new(
            inner,
            parslet.min,
            parslet.max,
            parslet.result_tag
          )
        end
      end
    end
  end
end
