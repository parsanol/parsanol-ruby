# frozen_string_literal: true

# Literal string matcher. Matches an exact sequence of characters.
#
# @example Match literal text
#   str('hello')  # matches exactly 'hello'
#
module Parsanol
  module Atoms
    class Str < Parsanol::Atoms::Base
      # @return [String] the literal to match
      attr_reader :str

      # Creates a new string matcher.
      #
      # @param text [String, Object] the literal string to match
      def initialize(text)
        super()
        @str = text.to_s
        @byte_size = @str.bytesize
        @char_count = @str.length

        # Pre-built error messages (frozen)
        @early_eof_msg = "Unexpected end of input"
        @mismatch_msg = "Expected #{@str.inspect}, but got "

        # Optimization: single-char fast path
        @single_char = (@str if @char_count == 1)
      end

      # Attempts to match the literal at current position.
      #
      # @param source [Parsanol::Source] input
      # @param context [Parsanol::Atoms::Context] context
      # @param _consume_all [Boolean] ignored
      # @return [Array(Boolean, Object)] result
      def try(source, context, _consume_all)
        # Single-character optimization
        return single_char_match(source, context) if @single_char

        # Multi-character matching
        multi_char_match(source, context)
      end

      # String representation.
      #
      # @param _prec [Integer] unused
      # @return [String]
      def to_s_inner(_prec)
        "'#{@str}'"
      end

      # Simple atoms don't benefit from caching.
      #
      # @return [Boolean]
      def cached?
        false
      end

      # Produces flat results (Slice).
      #
      # @return [Boolean]
      def flat?
        true
      end

      # FIRST set is this atom itself.
      #
      # @return [Set]
      def compute_first_set
        Set.new([self])
      end

      private

      # Fast path for single-character strings.
      def single_char_match(source, context)
        if source.chars_left < 1
          return context.err(self, source,
                             @early_eof_msg)
        end

        pos = source.pos
        slice = source.consume(1)

        return ok(slice) if slice.content == @single_char

        source.bytepos = pos
        context.err_at(self, source, [@mismatch_msg, slice], pos)
      end

      # Standard path for multi-character strings.
      def multi_char_match(source, context)
        if source.chars_left < @char_count
          return context.err(self, source,
                             @early_eof_msg)
        end

        pos = source.pos
        slice = source.consume(@char_count)

        return ok(slice) if slice.content == @str

        source.bytepos = pos
        context.err_at(self, source, [@mismatch_msg, slice], pos)
      end
    end
  end
end
