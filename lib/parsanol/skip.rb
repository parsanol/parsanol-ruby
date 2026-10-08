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
    #
    # +captures+ (parsanol-ruby#180) maps capturer rule names to kind
    # labels (`skip :trivia, capture: { line_comment: :line }`); the
    # injected wrapper becomes a TriviaCapture whose units matching a
    # capturer's leading literal attach to the next Named capture
    # under `comments:` — the PARG `skip = trivia capture: comments`
    # shape. Whitespace-shaped units never record.
    def self.inject(parser_instance, root_atom, skip_rule_name, captures: nil,
                    whitespace: nil)
      skip_atom = parser_instance.__send__(skip_rule_name)
      skip_atom = skip_atom.parslet while skip_atom.is_a?(Atoms::Entity)

      if VM::Compiler.new.nullable?(skip_atom)
        raise GrammarError,
              "skip rule must be non-nullable: a skip that can match " \
              "empty loops forever at injection points"
      end

      markers = capturer_markers(parser_instance, captures)
      whitespace_kind = whitespace&.to_sym
      injector = Injector.new(skip_atom, markers, whitespace_kind)
      [injector.inject(root_atom, entry: true), skip_atom]
    end

    # Derives each capturer's leading literal (the leftmost Str the
    # rule can start with) and keys the marker table by it — the same
    # derivation the PARG compiler applies to its skip declaration. A
    # declared capturer without a derivable, non-blank literal is a
    # declaration error: its units could never be told apart from
    # whitespace-shaped trivia and it would silently record nothing.
    def self.capturer_markers(parser_instance, captures)
      return nil if captures.nil? || captures.empty?

      captures.each_with_object({}) do |(rule_name, kind), markers|
        atom = parser_instance.__send__(rule_name)
        atom = atom.parslet while atom.is_a?(Atoms::Entity)
        literal = leading_literal(atom)
        if literal.nil? || literal.strip.empty?
          raise GrammarError,
                "skip capturer #{rule_name.inspect} has no leading " \
                "literal: its units cannot be told apart from " \
                "whitespace-shaped trivia"
        end
        markers[literal] = kind || rule_name
      end
    end

    # The leftmost literal the atom can start with, or nil when the
    # shape is not literal-led (alternatives with disagreeing
    # branches, regexes, lookaheads).
    def self.leading_literal(atom)
      case atom
      when Atoms::Str then atom.str
      when Atoms::Sequence
        atom.parslets.each do |child|
          literal = leading_literal(child)
          return literal if literal
        end
        nil
      when Atoms::Alternative
        first = nil
        atom.alternatives.each do |branch|
          literal = leading_literal(branch)
          return nil if literal.nil? || (first && literal != first)

          first ||= literal
        end
        first
      when Atoms::Repetition
        atom.min&.positive? ? leading_literal(atom.parslet) : nil
      when Atoms::Named, Atoms::Capture, Atoms::Ignored, Atoms::Trivia
        leading_literal(atom.parslet)
      end
    end

    # The injection walk. Mirrors the PARG compiler's semantics:
    # sequences interleave the wrapper before every child, alternatives
    # and repetitions descend, named captures descend (spans stay
    # clean — the wrapper is Trivia: Ignored + diagnostics
    # transparency), bare terminals gain a leading wrapper, and the
    # entry root takes leading and trailing wrappers.
    # The walk is a pure function of the atom subtree, so results are
    # memoized: dense cross-referencing grammars (expressir's ~250
    # rules) revisit shared subtrees once per referencing path, which
    # made the path-scoped visited-set exponential — a 25-rule
    # Fibonacci-shaped grammar took 6.2s to build (parsanol-ruby#180
    # side observation). In-progress atoms mark a cycle re-entry and
    # return raw, exactly as the path-scoped set did.
    class Injector
      def initialize(skip_atom, markers = nil, whitespace_kind = nil)
        @skip_atom = skip_atom
        @markers = markers
        @whitespace_kind = whitespace_kind
        @wrapper_ids = {}.compare_by_identity
        @memo = {}.compare_by_identity
        @in_progress = {}.compare_by_identity
      end

      def inject(atom, entry: false)
        injected = walk(atom)
        return injected unless entry

        Atoms::Sequence.new(maybe, injected, maybe)
      end

      private

      def maybe
        @maybe ||= begin
          inner = Atoms::Repetition.new(@skip_atom, 0, 1)
          wrapper =
            if @markers || @whitespace_kind
              Atoms::TriviaCapture.new(inner, @markers,
                                       whitespace_kind: @whitespace_kind)
            else
              Atoms::Trivia.new(inner)
            end
          @wrapper_ids[wrapper] = true
          wrapper
        end
      end

      def wrapper?(atom)
        @wrapper_ids.key?(atom)
      end

      def walk(atom)
        cached = @memo[atom]
        return cached if cached
        return atom if @in_progress.key?(atom)
        return atom if atom.equal?(@skip_atom)

        @in_progress[atom] = true
        injected =
          case atom
          when Atoms::Sequence
            out = []
            atom.parslets.each do |child|
              injected = walk(child)
              out << maybe unless wrapper?(injected) || injected.is_a?(Atoms::Trivia)
              out << injected
            end
            out.length == 1 ? out.first : Atoms::Sequence.new(*out)
          when Atoms::Alternative
            Atoms::Alternative.new(*atom.alternatives.map { |a| walk(a) })
          when Atoms::Repetition
            if wrapper?(atom)
              atom
            else
              Atoms::Repetition.new(walk(atom.parslet), atom.min, atom.max,
                                    atom.result_tag)
            end
          when Atoms::Named
            Atoms::Named.new(walk(atom.parslet), atom.name)
          when Atoms::Lookahead
            Atoms::Lookahead.new(walk(atom.bound_parslet), atom.positive)
          when Atoms::Ignored
            Atoms::Ignored.new(walk(atom.wrapped_atom))
          when Atoms::Entity
            # Rule bodies own their injection when the grammar declares
            # skip on every rule (PARG); in the DSL surface the root tree
            # is walked once, so descend through resolved bodies with the
            # identity visited-set guarding recursion.
            begin
              walk(atom.parslet)
            rescue StandardError
              atom
            end
          when Atoms::Str, Atoms::Re
            Atoms::Sequence.new(maybe, atom)
          else
            atom
          end
        @in_progress.delete(atom)
        @memo[atom] = injected
        injected
      end
    end
  end
end
