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
          document.bindings.each_value do |list|
            Array(list).each { |binding| bound << binding.capture }
          end

          # No bindings section = the author opted out of binding (a
          # parse-only grammar): uncovered captures are not oversights.
          # The orphan half moved to BindingPaths, whose resolution
          # failures fail the build (ruby#308 v2) -- a warning could
          # never fire past that error.
          dead = document.bindings.empty? ? [] : all_captures - bound.uniq
          dead.map do |capture|
            "capture #{capture.inspect} is bound by no bindings section -- " \
              "ship the binding beside the capture, or drop the capture"
          end
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

      # ruby#308 v2: compile-time binding resolution. The CAPTURE a
      # binding reads must exist in its rule's capture subtree (the
      # orphan check, now with teeth); a `x[]...` path needs that
      # capture to sit under a repetition (the flattening presumes
      # iteration). The path's names are output naming -- free -- but
      # its SHAPE is a contract: one `[]` level, one dotted-free leaf,
      # and a nested path always carries the marker. Anything the
      # runtime would silently bind as nothing fails the build instead,
      # naming the rule, the path, and the offending segment.
      class BindingPaths
        def errors(document, _compiler)
          document.bindings.flat_map do |rule, bindings|
            tree = CaptureTree.new(document, rule)
            Array(bindings).flat_map { |binding| resolve(rule, binding, tree) }
          end
        end

        def warnings(_document, _compiler) = []
        def advisory? = false

        private

        # The validated language is what the runtime honors today:
        # `capture` and `capture[].leaf` -- one repetition level, one
        # leaf. Anything else fails the build instead of silently
        # binding nothing (the runtime's leaf lookup would miss).
        def resolve(rule, binding, tree)
          capture = binding.capture.to_s
          path = binding.path.to_s
          return [unresolvable(rule, path, path)] if path.include?(".") && !path.include?("[]")

          scope = tree.scope
          return [unresolvable(rule, capture, capture)] unless scope.key?(capture)
          return [] unless path.include?("[]")

          levels = path.split("[]", -1)
          return [unresolvable(rule, path, "[]")] if levels.size > 2

          leaf = levels[1].to_s.delete_prefix(".")
          return [unresolvable(rule, path, "[]")] unless scope[capture][0]
          return [unresolvable(rule, path, leaf)] if leaf.empty? || leaf.include?(".")

          []
        end

        def unresolvable(rule, path, segment)
          "binding on #{rule.inspect}: path #{path.inspect} does not resolve -- " \
            "segment #{segment.inspect} names no capture at that position " \
            "(supported: capture, capture[].leaf)"
        end
      end

      # The capture TREE a binding path resolves against: per capture,
      # whether it sits under a repetition and which captures its
      # subtree contains (transitively -- the runtime's capture lookup
      # is subtree-wide too).
      class CaptureTree
        def initialize(document, rule)
          @document = document
          @scope = Hash.new { |hash, name| hash[name] = [false, []] }
          walk(document.rules[rule], { rule => true }) if document.rules.key?(rule)
        end

        def scope
          @scope
        end

        def walk(node, seen, under_rep: false, inside: [])
          case node.kind
          when :cap
            entry = @scope[node.a]
            # `1*x as n` compiles to cap(n, rep): the capture WRAPS its
            # repetition, so a repetition in either position makes the
            # capture repeated.
            repeated = under_rep || node.b&.kind == :rep
            entry[0] ||= repeated
            inside.each { |parent| entry[1] |= [parent] unless entry[1].include?(parent) }
            walk(node.b, seen, under_rep: repeated, inside: inside + [node.a])
          when :ref
            rule = node.a
            return if seen[rule]

            seen[rule] = true
            target = @document.rules[rule]
            walk(target, seen, under_rep: under_rep, inside: inside) if target
          when :alt, :seq
            node.a.each { |child| walk(child, seen, under_rep: under_rep, inside: inside) }
          when :pred
            walk(node.b, seen, under_rep: under_rep, inside: inside)
          when :rep
            walk(node.a, seen, under_rep: true, inside: inside)
          when :opt
            walk(node.a, seen, under_rep: under_rep, inside: inside)
          end
        end
      end

      register :binding_paths, BindingPaths.new

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

      # ruby#307 B5 --suggest-upgrades: machine-applicable authoring
      # upgrades. NOT registered -- its output is a suggestion surface
      # (parg lint --suggest-upgrades), never a compile diagnostic and
      # never part of the envelope.
      class CoreRuleDuplicates
        def warnings(document, _compiler)
          document.rules.filter_map do |name, node|
            next if Compiler::BUILTIN_CLASSES.key?(name)

            core = core_rule_for(node)
            next if core.nil?

            "rule #{name.inspect} duplicates the core rule #{core} -- " \
              "reference #{core} instead (or keep the local spelling deliberate)"
          end
        end

        def errors(_document, _compiler) = []
        def advisory? = true

        private

        def core_rule_for(node)
          case node.kind
          when :class
            Compiler::BUILTIN_CLASSES.find { |_, ranges| normalized(ranges) == normalized(node.a) }&.first
          when :seq
            crlf?(node) ? "CRLF" : nil
          end
        end

        def crlf?(node)
          parts = node.a
          parts.length == 2 &&
            parts.all? { |part| part.kind == :class } &&
            normalized(parts[0].a) == [[0x0D, 0x0D]] &&
            normalized(parts[1].a) == [[0x0A, 0x0A]]
        end

        def normalized(ranges)
          ranges.map(&:sort).sort
        end
      end
    end
  end
end
