# frozen_string_literal: true

# Base class for AST visitors following the Visitor pattern
# This separates tree traversal logic from transformation logic
# making the code more maintainable and extensible.
module Parsanol
  # Base visitor class that traverses the Parslet AST
  # Subclasses override visit_* methods to perform transformations
  class ASTVisitor
    # Visit a parslet and its children
    # Subclasses should override specific visit_* methods
    # @param parslet [Parsanol::Atoms::Base] parslet to visit
    # @return [Parsanol::Atoms::Base] transformed parslet
    def visit(parslet)
      case parslet
      when Parsanol::Atoms::Sequence
        visit_sequence(parslet)
      when Parsanol::Atoms::Alternative
        visit_alternative(parslet)
      when Parsanol::Atoms::Repetition
        visit_repetition(parslet)
      when Parsanol::Atoms::Lookahead
        visit_lookahead(parslet)
      when Parsanol::Atoms::Named
        visit_named(parslet)
      when Parsanol::Atoms::Str
        visit_str(parslet)
      when Parsanol::Atoms::Re
        visit_re(parslet)
      else
        # Leaf nodes or unknown types - return as-is
        parslet
      end
    end

    # Visit a sequence node
    # Default implementation visits children and reconstructs if changed
    # @param parslet [Parsanol::Atoms::Sequence] sequence to visit
    # @return [Parsanol::Atoms::Base] transformed sequence
    def visit_sequence(parslet)
      new_parslets = parslet.parslets.map { |p| visit(p) }
      if new_parslets == parslet.parslets
        parslet
      else
        Parsanol::Atoms::Sequence.new(*new_parslets)
      end
    end

    # Visit an alternative node
    # Default implementation visits children and reconstructs if changed
    # @param parslet [Parsanol::Atoms::Alternative] alternative to visit
    # @return [Parsanol::Atoms::Base] transformed alternative
    def visit_alternative(parslet)
      new_alternatives = parslet.alternatives.map { |p| visit(p) }
      if new_alternatives == parslet.alternatives
        parslet
      else
        Parsanol::Atoms::Alternative.new(*new_alternatives)
      end
    end

    # Visit a repetition node
    # Default implementation visits child and reconstructs if changed
    # @param parslet [Parsanol::Atoms::Repetition] repetition to visit
    # @return [Parsanol::Atoms::Base] transformed repetition
    def visit_repetition(parslet)
      new_parslet = visit(parslet.parslet)
      if new_parslet.equal?(parslet.parslet)
        parslet
      else
        Parsanol::Atoms::Repetition.new(
          new_parslet,
          parslet.min,
          parslet.max,
          parslet.instance_variable_get(:@tag)
        )
      end
    end

    # Visit a lookahead node
    # Default implementation visits child and reconstructs if changed
    # @param parslet [Parsanol::Atoms::Lookahead] lookahead to visit
    # @return [Parsanol::Atoms::Base] transformed lookahead
    def visit_lookahead(parslet)
      new_bound = visit(parslet.bound_parslet)
      if new_bound.equal?(parslet.bound_parslet)
        parslet
      else
        Parsanol::Atoms::Lookahead.new(new_bound, parslet.positive)
      end
    end

    # Visit a named node
    # Default implementation visits child and reconstructs if changed
    # @param parslet [Parsanol::Atoms::Named] named to visit
    # @return [Parsanol::Atoms::Base] transformed named
    def visit_named(parslet)
      new_parslet = visit(parslet.parslet)
      if new_parslet.equal?(parslet.parslet)
        parslet
      else
        Parsanol::Atoms::Named.new(new_parslet, parslet.name)
      end
    end

    # Visit a string literal node
    # Default implementation returns as-is (leaf node)
    # @param parslet [Parsanol::Atoms::Str] string to visit
    # @return [Parsanol::Atoms::Base] transformed string
    def visit_str(parslet)
      parslet
    end

    # Visit a regex node
    # Default implementation returns as-is (leaf node)
    # @param parslet [Parsanol::Atoms::Re] regex to visit
    # @return [Parsanol::Atoms::Base] transformed regex
    def visit_re(parslet)
      parslet
    end
  end
end
