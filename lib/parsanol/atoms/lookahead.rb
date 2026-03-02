# frozen_string_literal: true

# Lookahead assertion - checks for pattern presence/absence without consuming.
# Position is always restored after the check.
#
# @example Positive lookahead (must be present)
#   str('foo').present?  # succeeds if 'foo' ahead
#
# @example Negative lookahead (must not be present)
#   str('foo').absent?   # succeeds if 'foo' not ahead
#
module Parsanol
  module Atoms
    class Lookahead < Parsanol::Atoms::Base
      # @return [Boolean] true for positive, false for negative
      attr_reader :positive

      # @return [Parsanol::Atoms::Base] parser to check
      attr_reader :bound_parslet

      # Creates a new lookahead.
      #
      # @param parser [Parsanol::Atoms::Base] parser to check
      # @param is_positive [Boolean] positive vs negative
      def initialize(parser, is_positive = true)
        super()
        @positive = is_positive
        @bound_parslet = parser

        # Pre-built error components
        @should_start = ['Input should start with ', parser].freeze
        @should_not_start = ['Input should not start with ', parser].freeze
      end

      # Tests lookahead without consuming input.
      #
      # @param source [Parsanol::Source] input
      # @param context [Parsanol::Atoms::Context] context
      # @param consume_all [Boolean] ignored
      # @return [Array(Boolean, Object)] result
      def try(source, context, consume_all)
        # Save position - never consume
        saved = source.bytepos

        matched, = @bound_parslet.apply(source, context, consume_all)

        # Always restore
        source.bytepos = saved

        if @positive
          # Positive: succeed if matched
          return ok(nil) if matched

          context.err_at(self, source, @should_start, source.bytepos)
        else
          # Negative: succeed if not matched
          return context.err_at(self, source, @should_not_start, source.bytepos) if matched

          ok(nil)
        end
      end

      precedence LOOKAHEAD

      # String representation.
      #
      # @param prec [Integer] precedence
      # @return [String]
      def to_s_inner(prec)
        symbol = @positive ? '&' : '!'
        "#{symbol}#{@bound_parslet.to_s(prec)}"
      end

      # FIRST set is always EPSILON (zero-width).
      #
      # @return [Set]
      def compute_first_set
        Set.new([Parsanol::FirstSet::EPSILON])
      end
    end
  end
end
