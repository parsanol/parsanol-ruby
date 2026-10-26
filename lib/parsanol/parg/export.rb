# frozen_string_literal: true

module Parsanol
  module PARG
    # Lowers a compiled artifact to a decoder-facing grammar form
    # (ruby#321): XGrammar's EBNF dialect first. One artifact feeding
    # both worlds is the point — human-facing PARG with provenance,
    # tests, and five-engine replay on one side; the constrained
    # decoder on the other.
    #
    # The supported subset lowers 1:1. Everything the target cannot
    # express — lookaround, behind-guards, custom atoms, fold groups —
    # is rejected NAMING the construct: the importer philosophy in
    # reverse, never silently dropped.
    module Export
      class Error < StandardError
      end

      TARGETS = %i[xgrammar].freeze

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
          else raise Error, "unknown export target #{target.inspect} (supported: #{TARGETS.join(', ')})"
          end
        end
      end

      # XGrammar's EBNF: one rule per entry; literals "…"; classes
      # […]; suffixes * + ? {m,n}. Ordered choice is lost — the target
      # resolves ambiguity its own way; the export lowers alternatives
      # in the same order and the round-trip corpus pins acceptance
      # equality. The artifact wire has no rule boundaries (all atoms
      # inline), so each entry lowers as one expression.
      class Xgrammar
        def initialize(artifact_json, recovery: false)
          @envelope = JSON.parse(artifact_json)
          @recovery = recovery
        end

        def call
          rules = @envelope["entries"].map do |entry, meta|
            grammar = meta.fetch("grammar")
            "#{entry}_entry ::= #{lower_entry(entry, grammar)}"
          end
          "#{rules.join("\n")}\n"
        end

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
          atoms = grammar.fetch('atoms')
          body = lower(atoms, grammar.fetch('root'))
          return body unless @recovery

          pattern = @envelope.dig('entries', entry, 'resync')
          return body unless pattern

          spine = repetition_spine(atoms, grammar.fetch('root'))
          unless spine
            unsupported('recovery export: the entry root is not a repetition spine')
          end
          junk = lower(pattern.fetch('atoms'), pattern.fetch('root'))
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
          when 'Named', 'Entity' then repetition_spine(atoms, fields.fetch('atom'))
          when 'Repetition'
            return nil unless fields['max'].nil?

            fields.fetch('atom')
          end
        end

        def lower(atoms, index)
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
        end

        def suffix(body, min, max)
          min ||= 0
          if min.zero? && max.nil?
            "#{wrap(body)}*"
          elsif min == 1 && max.nil?
            "#{wrap(body)}+"
          elsif min.zero? && max == 1
            "#{wrap(body)}?"
          else
            "#{wrap(body)}{#{min},#{max || ''}}"
          end
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

          if (folded = pattern[/\A\(\?i:(.*)\)\z/m, 1])
            return expand_fold(folded, pattern)
          end

          unsupported("regex pattern #{pattern.inspect}")
        end

        # Class endpoints \u00ff / \u{10ffff} spell as the literal
        # characters — XGrammar's EBNF classes are UTF-8 text and
        # accept them; emitting the escapes raw fails the target's
        # lexer instead.
        def de_escape_class(pattern)
          pattern
            .gsub(/\\u\{([0-9a-fA-F]+)\}/) { [$1.to_i(16)].pack('U') }
            .gsub(/\\u([0-9a-fA-F]{4})/) { [$1.to_i(16)].pack('U') }
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
          raise Error, "xgrammar export: #{what} has no XGrammar equivalent"
        end
      end
    end
  end
end
