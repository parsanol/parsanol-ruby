# frozen_string_literal: true

module Parsanol
  module PARG
    # Registry of compile-time lints (OCP): each lint is a class with
    # `errors(document, compiler)` and `warnings(document, compiler)` —
    # both pure (data in, data out; no side effects). The compiler runs
    # every registered lint; adding a lint never touches the pipeline.
    # Lints use the compiler only as an analysis facade (find_left_cycle,
    # first_set, nullable?).
    module Lints
      class << self
        def register(name, strategy)
          strategies[name.to_sym] = strategy
        end

        def errors(document, compiler)
          strategies.values.flat_map { |strategy| strategy.errors(document, compiler) }
        end

        def warnings(document, compiler)
          strategies.values.flat_map { |strategy| strategy.warnings(document, compiler) }
        end

        def strategies
          @strategies ||= {}
        end
      end

      # Left recursion (direct + indirect, leftmost positions) rejects
      # the compile: every PEG engine would loop forever.
      class LeftRecursion
        def errors(document, compiler)
          document.rules.filter_map do |name, _node|
            cycle = compiler.find_left_cycle(name)
            "left recursion detected: #{cycle.join(' -> ')}" if cycle
          end
        end

        def warnings(_document, _compiler) = []
      end

      # Ordered-choice hazards: the class of silent failures PEGs are
      # known for, turned into build failures plus recorded warnings.
      class Alternatives
        def errors(document, compiler)
          checked(document, compiler).flat_map { |result| result[:errors] }
        end

        def warnings(document, compiler)
          checked(document, compiler).flat_map { |result| result[:warnings] }
        end

        private

        def checked(document, compiler)
          @checked ||= {}
          @checked[[document.object_id, compiler.object_id]] ||= begin
            results = []
            document.rules.each do |name, node|
              next unless node.kind == :alt

              results.concat(check_alternatives(name, node, compiler))
            end
            results
          end
        end

        def check_alternatives(name, node, compiler)
          results = []
          branches = node.a
          branches.each_with_index do |branch, index|
            if compiler.nullable?(branch) && index < branches.length - 1
              results << { errors: [empty_shadow_error(name, index + 1)], warnings: [] }
            end
            branches[(index + 1)..].each_with_index do |later, j|
              results << compare_branches(name, branch, index + 1, later, index + j + 2, compiler)
            end
          end
          results
        end

        def empty_shadow_error(name, branch_number)
          "rule #{name}: branch #{branch_number} can match empty input and " \
            "shadows all later branches"
        end

        def compare_branches(name, earlier, earlier_n, later, later_n, compiler)
          earlier_lit = literal_string(earlier)
          later_lit = literal_string(later)
          if earlier_lit && later_lit
            if earlier_lit == later_lit
              return { errors: ["rule #{name}: branches #{earlier_n} and #{later_n} are identical"], warnings: [] }
            elsif later_lit.start_with?(earlier_lit)
              return { errors: [shadow_error(name, earlier_n, earlier_lit, later_n, later_lit)], warnings: [] }
            end
          end
          first_earlier = compiler.first_set(earlier) - [Compiler::EPS]
          first_later = compiler.first_set(later) - [Compiler::EPS]
          if first_earlier.include?(Compiler::ANY) || first_later.include?(Compiler::ANY)
            return { errors: [], warnings: [order_warning(name, earlier_n, later_n, "first set not statically known")] }
          end
          return { errors: [], warnings: [] } if !first_earlier.intersect?(first_later)

          { errors: [],
            warnings: [order_warning(name, earlier_n, later_n, "shared first bytes; ordered choice is decisive")] }
        end

        def shadow_error(name, earlier_n, earlier_lit, later_n, later_lit)
          "rule #{name}: branch #{earlier_n} (#{earlier_lit.inspect}) shadows " \
            "branch #{later_n} (#{later_lit.inspect}) — reorder longest-first or " \
            "the shorter always wins"
        end

        def order_warning(name, earlier_n, later_n, reason)
          "rule #{name}: branches #{earlier_n} and #{later_n} are order-dependent (#{reason})"
        end

        def literal_string(node)
          case node.kind
          when :lit then node.a
          when :seq
            node.a.map { |child| literal_string(child) }.join if node.a.all? { |child| child.kind == :lit }
          end
        end
      end

      # TODO.sota/9 T1/T2 lints (ruby#307): the core-rule prelude and
      # the brace form both carry a migration path — the lint carries
      # the suggestion. Core-rule shadows are deliberate-compatibility
      # (a local rule wins), so they are warnings, never errors.
      class CoreRuleStyle
        CORE_NAMES = (
          Compiler::BUILTIN_CLASSES.keys + Compiler::STRUCTURED_CORE_RULE_NAMES
        ).freeze

        def warnings(document, _compiler)
          shadows = document.rules.keys.select { |name| CORE_NAMES.include?(name) }
          shadow_warnings = shadows.map do |name|
            "rule #{name}: shadows the RFC 5234 core rule — drop the local " \
              "definition unless the narrowing is deliberate"
          end
          shadow_warnings + style_mixing_warning(document)
        end

        def errors(_document, _compiler) = []

        private

        def style_mixing_warning(document)
          brace = document.brace_rules.size
          line = document.rules.size - brace
          return [] if brace.zero? || line.zero?
          return [] if document.rules.size < 4

          ["grammar mixes brace (#{brace}) and line (#{line}) rule bodies — " \
           "pick one style per grammar"]
        end
      end

      register :left_recursion, LeftRecursion.new
      register :core_rule_style, CoreRuleStyle.new
      register :alternatives, Alternatives.new

      # An unbounded repetition whose body can match empty input is an
      # INVALID GRAMMAR: the parse can never terminate, and any VM that
      # tolerates it allocates without bound. Rejected at compile time —
      # unboundedness is a grammar-validity property, not a runtime
      # hazard to be hardened against.
      class Repetitions
        def errors(document, compiler)
          document.rules.flat_map do |name, node|
            walk(name, node, compiler)
          end
        end

        def warnings(_document, _compiler) = []

        private

        def walk(name, node, compiler)
          return [] if node.nil?

          kind = node.kind
          errors =
            if kind == :rep && node.c.nil? && compiler.nullable?(node.a)
              ["rule #{name}: repetition body can match empty input — " \
               "unbounded repetition is an invalid grammar"]
            else
              []
            end
          children =
            case kind
            when :rep, :opt then [node.a]
            when :pred, :cap then [node.b]
            when :seq, :alt then node.a
            else []
            end
          errors + children.flat_map { |child| walk(name, child, compiler) }
        end
      end
      register :repetitions, Repetitions.new
    end
  end
end
