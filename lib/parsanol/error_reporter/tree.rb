# frozen_string_literal: true

module Parsanol
  module ErrorReporter
    # Default error reporter that builds a hierarchical tree of failure causes.
    # Each parse failure creates a Cause node that can contain child causes
    # from nested parse attempts.
    #
    # The resulting error tree mirrors the grammar structure, making it easy
    # to understand which parts of the grammar failed and why.
    #
    # @example
    #   reporter = Parsanol::ErrorReporter::Tree.new
    #   parser.parse(input, reporter: reporter)
    #   # On failure, causes are available for inspection
    #
    # Inspired by error tree reporting patterns in parser generators.
    #
    class Tree < Base
      # Records a parse failure at the current source position.
      # Creates a Cause node that may contain child causes from deeper
      # parsing levels.
      #
      # @param parser_atom [Parsanol::Atoms::Base] atom that failed to match
      # @param src [Parsanol::Source] input source being parsed
      # @param msg [String, Array<String>] error description
      # @param nested_errors [Array<Cause>, nil] failures from inner parse attempts
      # @return [Parsanol::Cause] error cause node for this failure
      #
      def err(_parser_atom, src, msg, nested_errors = nil)
        error_pos = src.pos
        Cause.format(src, error_pos, msg, nested_errors)
      end

      # Records a parse failure at a specific position (not current position).
      # Used when the error occurred at a different location than where it's
      # being reported.
      #
      # @param parser_atom [Parsanol::Atoms::Base] atom that failed to match
      # @param src [Parsanol::Source] input source being parsed
      # @param msg [String, Array<String>] error description
      # @param error_pos [Integer] byte position where error actually occurred
      # @param nested_errors [Array<Cause>, nil] failures from inner parse attempts
      # @return [Parsanol::Cause] error cause node for this failure
      #
      def err_at(_parser_atom, src, msg, error_pos, nested_errors = nil)
        Cause.format(src, error_pos, msg, nested_errors)
      end

      # Notification that a parse succeeded.
      # Base implementation does nothing - see Contextual reporter for
      # success tracking.
      #
      # @param src [Parsanol::Source] input source being parsed
      # @return [nil]
      #
      def succ(_src)
        # Tree reporter doesn't track successes
        nil
      end
    end
  end
end
