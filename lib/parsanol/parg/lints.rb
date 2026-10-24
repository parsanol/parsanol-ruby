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
      # Advisory warnings are author guidance — they never ride the
      # envelope. The envelope's lint.order_warnings is a wire contract:
      # recompiling an unchanged grammar must reproduce it byte-for-byte,
      # so style/authoring findings (which fire on perfectly valid
      # grammars) stay out of it.
      Advisory = Struct.new(:message) do
        def to_s = message
      end

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

        # The envelope-carried subset: strategies that are not advisory.
        def envelope_warnings(document, compiler)
          strategies.values
            .reject { |strategy| strategy.respond_to?(:advisory?) && strategy.advisory? }
            .flat_map { |strategy| strategy.warnings(document, compiler) }
            .grep_v(Advisory)
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
              later = branches[(index + 1)..]
              results << if later.all? { |candidate| compiler.nullable?(candidate) }
                           # Both sides always succeed: the later branches are dead
                           # code, but acceptance is identical. Imported grammars
                           # legitimately produce this (unordered ABNF choice), so
                           # it is a warning, not the shadowing hazard.
                           { errors: [],
                             warnings: [Advisory.new(dead_nullable_warning(name, index + 1))] }
                         else
                           { errors: [empty_shadow_error(name, index + 1)], warnings: [] }
                         end
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

        def dead_nullable_warning(name, branch_number)
          "rule #{name}: branches after #{branch_number} are unreachable " \
            "(that branch always succeeds) — dead code, acceptance unchanged"
        end

        def compare_branches(name, earlier, earlier_n, later, later_n, compiler)
          earlier_lit = literal_string(earlier)
          later_lit = literal_string(later)
          earlier_fold = literal_fold(earlier)
          if earlier_lit && later_lit
            if earlier_lit == later_lit
              return { errors: ["rule #{name}: branches #{earlier_n} and #{later_n} are identical"], warnings: [] }
            elsif later_lit.start_with?(earlier_lit)
              return { errors: [shadow_error(name, earlier_n, earlier_lit, later_n, later_lit)], warnings: [] }
            elsif earlier_fold && earlier_lit.casecmp(later_lit).zero?
              # A case-insensitive earlier literal matches every casing
              # the later literal could: the later branch is dead (same
              # class as the prefix shadow above).
              return { errors: [case_shadow_error(name, earlier_n, earlier_lit, later_n, later_lit)], warnings: [] }
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

        def literal_fold(node)
          node.kind == :lit ? node.b : nil
        end

        def case_shadow_error(name, earlier_n, earlier_lit, later_n, later_lit)
          "rule #{name}: branch #{later_n} (#{later_lit.inspect}) can never match -- " \
            "branch #{earlier_n} is case-insensitive and already matches " \
            "#{earlier_lit.inspect} in every casing"
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
        def advisory? = true

        CORE_NAMES = (
          Compiler::BUILTIN_CLASSES.keys + Compiler::STRUCTURED_CORE_RULE_NAMES
        ).freeze

        def warnings(document, _compiler)
          authored = document.authored_rules || document.rules.keys
          shadows = authored.select { |name| CORE_NAMES.include?(name) }
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

      # ruby#307: authoring-contract lints. Each flags a grammar whose
      # artifact ships without something its consumers will want: pins,
      # docs, or a canonical entry placement. All warnings — the
      # constructs are legal; the omissions are the hazard.
      class AuthoringContracts
        def advisory? = true

        def warnings(document, compiler)
          unpinned(document) + undocumented(document, compiler)
        end

        def errors(_document, _compiler) = []

        private

        def unpinned(document)
          return [] unless document.tests.empty?

          ["grammar ships without a test section — an unpinned grammar is " \
           "unpinned behavior (accept/reject/capture tests ride the artifact " \
           "to every engine)"]
        end

        def undocumented(document, _compiler)
          # Injected core rules and left-recursion tier rules are
          # compiler-generated: they are reachable and necessarily
          # undocumented, and flagging them would be noise.
          injected = Compiler::BUILTIN_CLASSES.keys +
            Compiler::STRUCTURED_CORE_RULE_NAMES
          authored = document.authored_rules
          prefix = Compiler::LEFT_RECURSION_PREFIX
          entry_reachable(document).filter_map do |name|
            next if authored && !authored.include?(name)
            next if document.docs.key?(name)
            next if injected.include?(name)
            next if name.to_s.start_with?(prefix)

            "rule #{name}: entry-reachable without a ## doc comment — the " \
              "artifact ships docs for LSP hovers; a public rule without one " \
              "is a missing contract"
          end
        end

        # Rules reachable from any entry root through rule references.
        def entry_reachable(document)
          reachable = []
          seen = {}
          walk = lambda do |node|
            case node.kind
            when :ref
              name = node.a
              next if seen[name]

              seen[name] = true
              reachable << name
              walk.call(document.rules[name]) if document.rules.key?(name)
            when :alt, :seq then node.a.each { |child| walk.call(child) }
            when :cap, :pred then walk.call(node.b)
            when :rep, :opt then walk.call(node.a)
            end
          end
          document.entries.each_value do |root|
            walk.call(document.rules[root]) if document.rules.key?(root)
          end
          reachable
        end
      end

      register :authoring_contracts, AuthoringContracts.new
      # ruby#308 first slice: the two halves of binding coverage.
      # A binding that names a capture the grammar never produces binds
      # nothing; a capture no binding consumes is dead weight. Both are
      # advisory: the grammar compiles either way.
      class BindingCoverage
        def advisory? = true

        def warnings(document, _compiler)
          all_captures = produced_captures(document)
          bound = []
          orphan_warnings = []
          document.bindings.each do |rule, bindings|
            # Per-rule scope (ruby#308): a binding on rule R names a
            # capture R's own subtree produces -- not any capture anywhere.
            # Rules without local captures (pure dispatchers) fall back to
            # the grammar-wide set.
            rule_captures = reachable_captures(document, rule)
            scope = rule_captures.empty? ? all_captures : rule_captures
            Array(bindings).each do |binding|
              bound << binding.capture
              unless scope.include?(binding.capture)
                orphan_warnings << "binding on #{rule.inspect} references capture " \
                                   "#{binding.capture.inspect}, which that rule's subtree does " \
                                   "not produce"
              end
            end
          end

          # No bindings section = the author opted out of binding (a
          # parse-only grammar): uncovered captures are not oversights.
          dead = document.bindings.empty? ? [] : all_captures - bound.uniq
          dead_warnings = dead.map do |capture|
            "capture #{capture.inspect} is bound by no bindings section -- " \
              "ship the binding beside the capture, or drop the capture"
          end

          orphan_warnings + dead_warnings
        end

        def errors(_document, _compiler) = []

        private

        def produced_captures(document)
          captures = []
          seen = {}
          document.rules.each_value do |node|
            collect_captures(node, document, captures, seen)
          end
          captures.uniq
        end

        # Captures reachable from rule +name+ through its own body and
        # the bodies of the rules it references.
        def reachable_captures(document, name)
          captures = []
          seen = { name => true }
          node = document.rules[name]
          collect_captures(node, document, captures, seen) if node
          captures.uniq
        end

        def collect_captures(node, document, captures, seen)
          case node.kind
          when :cap
            captures << node.a
            collect_captures(node.b, document, captures, seen)
          when :ref
            rule = node.a
            return if seen[rule]

            seen[rule] = true
            target = document.rules[rule]
            collect_captures(target, document, captures, seen) if target
          when :alt, :seq
            node.a.each { |child| collect_captures(child, document, captures, seen) }
          when :pred
            collect_captures(node.b, document, captures, seen)
          when :rep, :opt
            collect_captures(node.a, document, captures, seen)
          end
        end
      end

      register :alternatives, Alternatives.new
      register :binding_coverage, BindingCoverage.new

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

      # ruby#307 lint completion: a rule no other rule references is
      # dead weight (unless it carries an entry); a rule referenced
      # exactly once is an inline candidate. Both advisory -- the
      # grammar is correct either way. Entry roots, the injected core
      # rules, and the left-recursion tier rules are exempt.
      class RuleUsage
        def advisory? = true

        def warnings(document, _compiler)
          counts = Hash.new(0)
          document.rules.each do |name, node|
            collect_refs(node, document, { name => true }, counts)
          end

          injected = Compiler::BUILTIN_CLASSES.keys +
            Compiler::STRUCTURED_CORE_RULE_NAMES
          resync_prefix = Compiler::LEFT_RECURSION_PREFIX
          document.rules.filter_map do |name, _node|
            next if injected.include?(name)
            next if name.to_s.start_with?(resync_prefix)
            next if document.entries.value?(name)

            case counts[name]
            when 0
              "rule #{name.inspect} is referenced by no rule -- dead " \
              "unless it is a future entry; drop it or wire it in"
            when 1
              "rule #{name.inspect} has exactly one reference -- inline " \
              "candidate (keep it if the name carries the domain)"
            end
          end
        end

        def errors(_document, _compiler) = []

        private

        def collect_refs(node, document, seen, counts)
          case node.kind
          when :ref
            rule = node.a
            counts[rule] += 1
            return if seen[rule]

            seen[rule] = true
            target = document.rules[rule]
            collect_refs(target, document, seen, counts) if target
          when :alt, :seq
            node.a.each { |child| collect_refs(child, document, seen, counts) }
          when :cap, :pred
            collect_refs(node.b, document, seen, counts)
          when :rep, :opt
            collect_refs(node.a, document, seen, counts)
          end
        end
      end
      register :rule_usage, RuleUsage.new
    end
  end
end
