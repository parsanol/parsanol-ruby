# frozen_string_literal: true

# Treetop-style expression parser for Parsanol.
#
# This module provides a parser and transform for converting treetop-style
# expression strings into Parsanol atoms. The implementation is pure Ruby
# and is not accelerated by the Rust native extension.
#
# == Why Pure Ruby?
#
# Expression parsing happens at grammar definition time (once per parser class),
# not during input parsing. The overhead is negligible for typical use cases.
# The resulting atoms can still be used with Rust-accelerated parsing.
#
# == Syntax Reference
#
#   Expression      ::= Alternative ('/' Alternative)*
#   Alternative     ::= Sequence+
#   Sequence        ::= Occurrence+
#   Occurrence      ::= Atom ('?' | '*' | '+' | '{min,max}')?
#   Atom            ::= '(' Expression ')' | '.' | String | CharClass
#   String          ::= "'" (escape | [^'])* "'"
#   CharClass       ::= '[' (escape | [^'])* ']'
#
# @note Whitespace is required before operators: 'a' ? not 'a'?
#
module Parsanol
  class Expression
    module Treetop
      # Parser for treetop-style expression strings.
      #
      # Parses expressions like "'a' 'b' ?" and produces a parse tree
      # that can be transformed into Parsanol atoms.
      #
      # @example
      #   parser = Parser.new
      #   tree = parser.parse("'a' / 'b'")
      #   # => {:alt=>[{:seq=>[{:string=>"a"}]}, {:seq=>[{:string=>"b"}]}]}
      #
      class Parser < Parsanol::Parser
        root(:expression)

        rule(:expression) { alternatives }

        # Alternative: 'a' / 'b'
        rule(:alternatives) do
          (simple >> (spaced('/') >> simple).repeat).as(:alt)
        end

        # Sequence by concatenation: 'a' 'b'
        rule(:simple) { occurrence.repeat(1).as(:seq) }

        # Occurrence modifiers: ?, *, +, {min,max}
        rule(:occurrence) do
          (atom.as(:repetition) >> spaced('*').as(:sign)) |
            (atom.as(:repetition) >> spaced('+').as(:sign)) |
            (atom.as(:repetition) >> repetition_spec) |
            (atom.as(:maybe) >> spaced('?')) |
            atom
        end

        rule(:atom) do
          (spaced('(') >> expression.as(:unwrap) >> spaced(')')) |
            dot |
            string |
            char_class
        end

        # Character class: [a-z], [0-9], etc.
        rule(:char_class) do
          (str('[') >>
            ((str('\\') >> any) | (str(']').absent? >> any)).repeat(1) >>
            str(']')).as(:match) >> space?
        end

        # Any character: .
        rule(:dot) { spaced('.').as(:any) }

        # String literal: 'hello'
        rule(:string) do
          str("'") >>
            ((str('\\') >> any) | (str("'").absent? >> any)).repeat.as(:string) >>
            str("'") >> space?
        end

        # Repetition specification: {1,3}, {2,}, {,5}
        rule(:repetition_spec) do
          spaced('{') >>
            integer.maybe.as(:min) >> spaced(',') >>
            integer.maybe.as(:max) >> spaced('}')
        end

        rule(:integer) do
          match['0-9'].repeat(1)
        end

        # Whitespace handling
        rule(:space) { match('\s').repeat(1) }
        rule(:space?) { space.maybe }

        # Helper: match string followed by optional whitespace
        def spaced(str)
          str(str) >> space?
        end
      end

      # Transform for converting parse trees to Parsanol atoms.
      #
      # @example
      #   tree = {:seq=>[{:string=>"a"}, {:string=>"b"}]}
      #   transform = Transform.new
      #   atom = transform.apply(tree)
      #   # => Sequence.new([Str.new('a'), Str.new('b')])
      #
      class Transform < Parsanol::Transform
        # Repetition with sign: * (zero+) or + (one+)
        rule(repetition: simple(:rep), sign: simple(:sign)) do
          min = sign == '+' ? 1 : 0
          Parsanol::Atoms::Repetition.new(rep, min, nil)
        end

        # Repetition with bounds: {min,max}
        rule(repetition: simple(:rep), min: simple(:min), max: simple(:max)) do
          Parsanol::Atoms::Repetition.new(
            rep,
            Integer(min || 0),
            (max && Integer(max)) || nil
          )
        end

        # Alternative: a / b
        rule(alt: subtree(:alt)) { Parsanol::Atoms::Alternative.new(*alt) }

        # Sequence: a b
        rule(seq: sequence(:s)) { Parsanol::Atoms::Sequence.new(*s) }

        # Unwrap parentheses
        rule(unwrap: simple(:u)) { u }

        # Optional: a ?
        rule(maybe: simple(:m)) { |d| d[:m].maybe }

        # String literal
        rule(string: simple(:s)) { Parsanol::Atoms::Str.new(s) }

        # Character class
        rule(match: simple(:m)) { Parsanol::Atoms::Re.new("[#{m}]") }

        # Any character: .
        rule(any: simple(:_a)) { Parsanol::Atoms::Re.new('.') }
      end
    end
  end
end
