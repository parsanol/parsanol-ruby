# frozen_string_literal: true

# Regular expression matcher.
#
# A plain character class matches one character. Like Parslet, a
# pattern with an embedded quantifier (match('a+') etc.) is a regex
# matched greedily at the current position: the whole regex match is
# consumed in one step.
#
# @example Character classes
#   match('[a-z]')  # matches one a-z character
#   match('a+')     # matches a maximal run of a (Parslet parity)
#   match('\d')     # matches one digit
#   any             # matches any character
#
module Parsanol
  module Atoms
    class Re < Parsanol::Atoms::Base
      # @return [String] the pattern string
      attr_reader :match

      # @return [Regexp] compiled pattern
      attr_reader :re

      # Creates a new regex matcher.
      #
      # @param pattern [String, Object] regex character class
      QUANTIFIER_RE = /[+*?]|\{\d+(?:,\s*\d*)?\}/.freeze

      def initialize(pattern)
        super()
        @match = pattern.to_s
        @re = Regexp.new(@match, Regexp::MULTILINE)
        # Embedded quantifier: one greedy regex match instead of a
        # single character (Parslet parity, GH-69).
        @quantified = QUANTIFIER_RE.match?(@match)

        # Extract pattern for display (strip delimiters)
        @display = @match.inspect[1..-2] || @match

        # Pre-built error messages
        @eof_error = "Unexpected end of input"
        @no_match_error = "Failed to match #{@display}"
      end

      # Matches one character against the pattern.
      #
      # @param source [Parsanol::Source] input
      # @param context [Parsanol::Atoms::Context] context
      # @param _consume_all [Boolean] ignored
      # @return [Array(Boolean, Object)] result
      def try(source, context, _consume_all)
        if @quantified
          # One greedy regex match (Parslet parity): consume the whole
          # match. A zero-length match is treated as no match so
          # repetitions always advance.
          matched = source.match_bytes(@re)
          return ok(source.consume_bytes(matched)) if matched&.positive?

          return context.err(self, source, @eof_error) if source.chars_left < 1
          return context.err(self, source, @no_match_error)
        end

        # Fast path: single-character class
        return ok(source.consume(1)) if source.matches?(@re)

        # No input left
        return context.err(self, source, @eof_error) if source.chars_left < 1

        # Character doesn't match
        context.err(self, source, @no_match_error)
      end

      # String representation.
      #
      # @param _prec [Integer] unused
      # @return [String]
      def to_s_inner(_prec)
        @display
      end

      # Simple atoms don't benefit from caching.
      #
      # @return [Boolean]
      def cached?
        false
      end

      # Produces flat results.
      #
      # @return [Boolean]
      def flat?
        true
      end

      # FIRST set is this atom.
      #
      # @return [Set]
      def compute_first_set
        Set.new([self])
      end
    end
  end
end
