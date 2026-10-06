# frozen_string_literal: true

module Parsanol
  # Skip-rule trivia injection for Ruby-DSL grammars (the PARG surface
  # compiles the same semantics into artifacts; see
  # Parsanol::PARG::Compiler#inject_skip_trivia). A parser declares
  # `skip :trivia`; the resolved rule's atom becomes the injected
  # optional trivia wrapper before every terminal of every rule body,
  # with the declaration's transitive closure exempt (the skip atom
  # must not contain itself).
  module Skip
    # +skip_rule_name+ resolves against the parser instance's rule
    # methods. Returns [injected_root, skip_atom] with the wrapper
    # built and the lint applied, or raises GrammarError for a
    # nullable skip.
    def self.inject(parser_instance, root_atom, skip_rule_name)
      skip_atom = parser_instance.__send__(skip_rule_name)
      skip_atom = skip_atom.parslet while skip_atom.is_a?(Atoms::Entity)

      if VM::Compiler.new.nullable?(skip_atom)
        raise GrammarError,
              "skip rule must be non-nullable: a skip that can match " \
              "empty loops forever at injection points"
      end

      injector = Injector.new(skip_atom)
      [injector.inject(root_atom, entry: true), skip_atom]
    end

    # The injection walk. Mirrors the PARG compiler's semantics:
    # sequences interleave the wrapper before every child, alternatives
    # and repetitions descend, named captures descend (spans stay
    # clean — the wrapper is Trivia: Ignored + diagnostics
    # transparency), bare terminals gain a leading wrapper, and the
    # entry root takes leading and trailing wrappers.
    class Injector
      def initialize(skip_atom)
        @skip_atom = skip_atom
        @wrapper_ids = {}.compare_by_identity
      end

      def inject(atom, entry: false)
        injected = walk(atom, {})
        return injected unless entry

        Atoms::Sequence.new(maybe, injected, maybe)
      end

      private

      def maybe
        @maybe ||= begin
          wrapper = Atoms::Trivia.new(Atoms::Repetition.new(@skip_atom, 0, 1))
          @wrapper_ids[wrapper] = true
          wrapper
        end
      end

      def wrapper?(atom)
        @wrapper_ids.key?(atom)
      end

      def walk(atom, visited)
        return atom if visited.key?(atom)
        return atom if atom.equal?(@skip_atom)

        visited = visited.merge(atom => true)
        case atom
        when Atoms::Sequence
          out = []
          atom.parslets.each do |child|
            injected = walk(child, visited)
            out << maybe unless wrapper?(injected) || injected.is_a?(Atoms::Trivia)
            out << injected
          end
          out.length == 1 ? out.first : Atoms::Sequence.new(*out)
        when Atoms::Alternative
          Atoms::Alternative.new(*atom.alternatives.map { |a| walk(a, visited) })
        when Atoms::Repetition
          if wrapper?(atom)
            atom
          else
            Atoms::Repetition.new(walk(atom.parslet, visited), atom.min, atom.max,
                                  atom.result_tag)
          end
        when Atoms::Named
          Atoms::Named.new(walk(atom.parslet, visited), atom.name)
        when Atoms::Lookahead
          Atoms::Lookahead.new(walk(atom.bound_parslet, visited), atom.positive)
        when Atoms::Ignored
          Atoms::Ignored.new(walk(atom.wrapped_atom, visited))
        when Atoms::Entity
          # Rule bodies own their injection when the grammar declares
          # skip on every rule (PARG); in the DSL surface the root tree
          # is walked once, so descend through resolved bodies with the
          # identity visited-set guarding recursion.
          begin
            walk(atom.parslet, visited)
          rescue StandardError
            atom
          end
        when Atoms::Str, Atoms::Re
          Atoms::Sequence.new(maybe, atom)
        else
          atom
        end
      end
    end
  end
end
