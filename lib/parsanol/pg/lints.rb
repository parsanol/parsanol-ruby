# frozen_string_literal: true

module Parsanol
  module PG
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

      register :left_recursion, LeftRecursion.new
      register :alternatives, Alternatives.new
    end
  end
end
