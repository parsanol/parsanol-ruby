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
        def call(artifact_json, target: :xgrammar)
          case target
          when :xgrammar then Xgrammar.new(artifact_json).call
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
        def initialize(artifact_json)
          @envelope = JSON.parse(artifact_json)
        end

        def call
          rules = @envelope["entries"].map do |entry, meta|
            grammar = meta.fetch("grammar")
            "#{entry}_entry ::= #{lower(grammar.fetch('atoms'), grammar.fetch('root'))}"
          end
          "#{rules.join("\n")}\n"
        end

        private

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
          return pattern if pattern.start_with?("[") && pattern.end_with?("]")

          if (folded = pattern[/\A\(\?i:(.*)\)\z/m, 1])
            return expand_fold(folded, pattern)
          end

          unsupported("regex pattern #{pattern.inspect}")
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
