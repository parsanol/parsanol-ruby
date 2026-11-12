# frozen_string_literal: true

module Parsanol
  module PARG
    # Lowers a compiled artifact to a decoder-facing grammar form
    # (ruby#321): XGrammar's EBNF dialect, and llguidance's Lark subset
    # (ruby#460). One artifact feeding both worlds is the point —
    # human-facing PARG with provenance, tests, and five-engine replay
    # on one side; the constrained decoder on the other.
    #
    # The supported subset lowers 1:1. Everything the target cannot
    # express — lookaround, behind-guards, custom atoms, fold groups —
    # is rejected NAMING the construct: the importer philosophy in
    # reverse, never silently dropped.
    module Export
      class Error < StandardError
      end

      TARGETS = %i[xgrammar llguidance].freeze

      class << self
        # `recovery: true` lowers each declared `resync <rule> = <pattern>`
        # as an escape alternative at the repetition spine: the target's
        # matcher then accepts exactly the strings the engines' recovery
        # path accepts — clean parses, and violate-then-resync parses
        # where the junk is emitted deliberately and the grammar closes
        # back over the continuation (ruby#321's partial-mask story).
        def call(artifact_json, target: :xgrammar, recovery: false)
          case target
          when :xgrammar then Xgrammar.new(artifact_json, recovery: recovery).call
          when :llguidance then Llguidance.new(artifact_json, recovery: recovery).call
          else raise Error, "unknown export target #{target.inspect} (supported: #{TARGETS.join(', ')})"
          end
        end
      end

      # The atom walk the two targets share: literals, classes,
      # sequences, alternations, repetitions, and the ASCII-fold
      # expansion. Subclasses supply the dialect: how one entry renders
      # (#render_entry), how repetitions spell (#suffix), and the
      # message prefix for unsupported constructs (#label).
      class Lowering
        MAX_EXPANSION = 64

        def initialize(artifact_json, label:, recovery: false)
          @envelope = JSON.parse(artifact_json)
          @recovery = recovery
          @label = label
          # The atom graph is a DAG with shared subtrees: a naive
          # recursive walk re-expands every shared reference along every
          # path — exponential on heavily-shared artifacts. A lowered
          # atom is a pure function of its index, so the cache makes the
          # walk linear (byte-identical output). Recursive grammars (the
          # self-hosted parg meta-grammar) are rejected NAMING the
          # re-entry: an inline EBNF unfold is infinite in principle.
          @memo = {}
          @in_progress = {}
        end

        def call
          rules = @envelope["entries"].map do |entry, meta|
            grammar = meta.fetch("grammar")
            render_entry(entry, lower_entry(entry, grammar))
          end
          "#{prologue}#{rules.join("\n")}\n"
        end

        def prologue = ""

        private

        # The recovery wrap mirrors the engines' resync contract: the
        # root must be a repetition spine (the same shape resync
        # recovery itself requires), and each declared resync pattern
        # becomes an alternative of the spine body — junk between
        # complete iterations is exactly what the recovery path
        # consumes and resumes. Inferred (undeclared) policies are the
        # trial scan and have no closed form here: the plain grammar
        # ships, and the differential reports the gap honestly.
        def lower_entry(entry, grammar)
          atoms = grammar.fetch("atoms")
          body = lower(atoms, grammar.fetch("root"))
          return body unless @recovery

          pattern = @envelope.dig("entries", entry, "resync")
          return body unless pattern

          spine = repetition_spine(atoms, grammar.fetch("root"))
          unless spine
            unsupported("recovery export: the entry root is not a repetition spine")
          end
          junk = lower(pattern.fetch("atoms"), pattern.fetch("root"))
          # A spine item is a body, optionally preceded by one junk
          # span: the engines scan forward to the first pattern match,
          # consume it as one annotated span, and resume with the next
          # iteration — which may be absent (trailing junk ends the
          # parse, recovered).
          "( #{body} | ( #{junk} ) ( #{body} )? )*"
        end

        # The lowerable body of the spine's repetition: Named/Entity
        # unwrapping down to the Repetition atom, unbounded (max nil).
        # Nil when the root is not that shape.
        def repetition_spine(atoms, index)
          tag, fields = atoms.fetch(index).first
          case tag
          when "Named", "Entity" then repetition_spine(atoms, fields.fetch("atom"))
          when "Repetition"
            return nil unless fields["max"].nil?

            fields.fetch("atom")
          end
        end

        def lower(atoms, index)
          key = [atoms.object_id, index]
          if @in_progress[key]
            raise Error, "#{@label}: recursive grammar: atom #{index} re-enters while being lowered " \
                         "(inline EBNF cannot carry recursive rules)"
          end

          @memo[key] ||= begin
            @in_progress[key] = true
            begin
              tag, fields = atoms.fetch(index).first
              case tag
              when "Str" then "\"#{fields['pattern'].gsub('\\') { '\\\\\\\\' }.gsub('"') { '\\\\\"' }}\""
              when "Re" then re_class(fields["pattern"])
              when "Sequence" then fields["atoms"].map { |child| lower(atoms, child) }.join(" ")
              when "Alternative" then "( #{fields['atoms'].map { |child| lower(atoms, child) }.join(' | ')} )"
              when "Repetition" then suffix(lower(atoms, fields["atom"]), fields["min"], fields["max"])
              when "Maybe" then suffix(lower(atoms, fields["atom"]), 0, 1)
              when "Named", "Entity" then "( #{lower(atoms, fields['atom'])} )"
              when "Lookahead" then unsupported("lookahead (!x / &x)")
              when "BehindGuard" then unsupported("behind-guard (!<x / &<x)")
              when "Custom" then unsupported("custom atom")
              when "Constant" then unsupported("constant atom")
              else unsupported("atom #{tag}")
              end
            ensure
              @in_progress.delete(key)
            end
          end
        end

        # Bounded repetition {m,n}: XGrammar spells it natively; targets
        # without the syntax expand mechanically (exact copies, then
        # optional copies up to the bound, or a `*` tail when unbounded)
        # — exact, never approximated, and rejected loudly past the
        # expansion cap so a pathological bound fails at export time.
        def suffix(body, min, max)
          min ||= 0
          if min.zero? && max.nil?
            "#{wrap(body)}*"
          elsif min == 1 && max.nil?
            "#{wrap(body)}+"
          elsif min.zero? && max == 1
            "#{wrap(body)}?"
          elsif native_bounded_repetition?
            "#{wrap(body)}{#{min},#{max || ''}}"
          else
            expand(body, min, max)
          end
        end

        def native_bounded_repetition? = false

        def expand(body, min, max)
          cap = max || min
          if cap > MAX_EXPANSION
            unsupported("bounded repetition {#{min},#{max || 'n'}} exceeds the " \
                        "#{MAX_EXPANSION}-item expansion cap")
          end

          parts = Array.new(min) { wrap(body) }
          if max.nil?
            parts << "#{wrap(body)}*" if min.positive?
          else
            parts += Array.new(max - min) { "#{wrap(body)}?" }
          end
          parts.join(" ")
        end

        def wrap(body)
          return body if body =~ /\A"[^"]*"\z/ || body =~ /\A\[[^\]]*\]\z/ || body =~ /\A[A-Za-z_][A-Za-z0-9_]*\z/

          "( #{body} )"
        end

        # A Re pattern the class form cannot carry is unsupported
        # rather than approximated — EXCEPT the ASCII fold literal:
        # (?i:...) expands mechanically to per-character [Xx] classes,
        # which IS the simple-case-fold semantics for ASCII. A non-ASCII
        # fold group needs a fold table the target does not have.
        def re_class(pattern)
          # Categories have no EBNF-class spelling: they must be
          # rejected naming the construct, never emitted raw (the
          # target's lexer rejects them, which fails the round trip
          # obscurely instead of at export time).
          if pattern.include?("\\p{")
            unsupported("unicode category #{pattern.inspect}")
          end

          return de_escape_class(pattern) if pattern.start_with?("[") && pattern.end_with?("]")

          folded = pattern[/\A\(\?i:(.*)\)\z/m, 1]
          return expand_fold(folded, pattern) if folded

          unsupported("regex pattern #{pattern.inspect}")
        end

        # Class endpoints ÿ / \u{10ffff} spell as the literal
        # characters — the targets' classes are UTF-8 text and
        # accept them; emitting the escapes raw fails the target's
        # lexer instead.
        def de_escape_class(pattern)
          pattern
            .gsub(/\\u\{([0-9a-fA-F]+)\}/) { [$1.to_i(16)].pack("U") }
            .gsub(/\\u([0-9a-fA-F]{4})/) { [$1.to_i(16)].pack("U") }
        end

        def expand_fold(text, pattern)
          unsupported("non-ASCII fold group #{pattern.inspect} -- the target has no fold table") unless text.ascii_only?

          text.chars.map do |char|
            if char =~ /[A-Za-z]/ && char.bytesize == 1
              "[#{char.upcase}#{char.downcase}]"
            elsif char == '"'
              '\\"'
            else
              char
            end
          end.join
        end

        def unsupported(what)
          raise Error, "#{@label}: #{what} has no #{label_name} equivalent"
        end

        def label_name = raise NotImplementedError
      end

      # XGrammar's EBNF: one rule per entry; literals "…"; classes
      # […]; suffixes * + ? {m,n}. Ordered choice is lost — the target
      # resolves ambiguity its own way; the export lowers alternatives
      # in the same order and the round-trip corpus pins acceptance
      # equality. The artifact wire has no rule boundaries (all atoms
      # inline), so each entry lowers as one expression.
      class Xgrammar < Lowering
        def initialize(artifact_json, recovery: false)
          super(artifact_json, label: "xgrammar export", recovery: recovery)
        end

        def render_entry(entry, body)
          "#{entry}_entry ::= #{body}"
        end

        private

        def native_bounded_repetition? = true

        def label_name = "XGrammar"
      end

      # llguidance's Lark subset (ruby#460): rules spell `name: body`,
      # the grammar enters through `start`, and there is no {m,n}
      # repetition — bounds expand mechanically (exact copies plus
      # optional copies, or a * tail when unbounded), capped and
      # rejected loudly past MAX_EXPANSION. Literals, classes,
      # sequences, alternations and the */+/? suffixes spell as in
      # Lark.
      class Llguidance < Lowering
        def initialize(artifact_json, recovery: false)
          super(artifact_json, label: "llguidance export", recovery: recovery)
        end

        def prologue
          "start: #{@envelope.fetch('default_entry')}_entry\n"
        end

        def render_entry(entry, body)
          "#{entry}_entry: #{body}"
        end

        private

        def label_name = "llguidance"
      end
    end
  end
end
