# frozen_string_literal: true

module Parsanol
  module ErrorReporter
    # Error reporter that tracks the deepest (furthest into input) parse failure.
    # Unlike Tree reporter which returns the most recent error, this reporter
    # keeps track of errors at the greatest input position, as these are typically
    # more useful for diagnosing what went wrong.
    #
    # The rationale is that errors occurring later in the input are more likely
    # to represent what the user intended - early failures often represent
    # alternative branches that simply didn't match.
    #
    # @example
    #   reporter = Parsanol::ErrorReporter::Deepest.new
    #   parser.parse(input, reporter: reporter)
    #   # The error cause will be the one at the furthest input position
    #
    # Inspired by "furthest failure" error reporting strategies in parser tools.
    #
    class Deepest < Base
      # @return [Parsanol::Cause, nil] the deepest cause encountered so far
      attr_reader :deepest_cause

      # Creates a new deepest error reporter.
      #
      def initialize
        @deepest_cause = nil
      end

      # Records an error at the current source position.
      # Updates the tracked deepest cause if this error is further into input.
      #
      # @param atom [Parsanol::Atoms::Base] atom that failed
      # @param source [Parsanol::Source] input source
      # @param message [String, Array] error message
      # @param children [Array, nil] child error causes
      # @return [Parsanol::Cause] the deepest known error cause
      #
      def err(_atom, source, message, children = nil)
        error_pos = source.pos
        cause = Cause.format(source, error_pos, message, children)
        deepest(cause)
      end

      # Records an error at a specific source position.
      # Updates the tracked deepest cause if this error is further into input.
      #
      # @param atom [Parsanol::Atoms::Base] atom that failed
      # @param source [Parsanol::Source] input source
      # @param message [String, Array] error message
      # @param pos [Integer] byte position of error
      # @param children [Array, nil] child error causes
      # @return [Parsanol::Cause] the deepest known error cause
      #
      def err_at(_atom, source, message, pos, children = nil)
        cause = Cause.format(source, pos, message, children)
        deepest(cause)
      end

      # Notification of successful parse (unused in this reporter).
      #
      # @param source [Parsanol::Source] input source
      # @return [nil]
      #
      def succ(_source)
        nil
      end

      # Evaluates a cause and returns the deepest known cause.
      # If the given cause is deeper than the currently tracked deepest,
      # updates tracking and returns the given cause. Otherwise returns
      # the previously tracked deepest cause.
      #
      # @param cause [Parsanol::Cause] error cause to evaluate
      # @return [Parsanol::Cause] the deepest known cause
      #
      def deepest(cause)
        # Find the deepest leaf in the cause tree
        _, leaf = find_deepest_leaf(cause)

        # Update tracking if this goes deeper than what we've seen
        if !@deepest_cause || leaf.pos >= @deepest_cause.pos
          @deepest_cause = leaf
          return cause
        end

        @deepest_cause
      end

      private

      # Recursively finds the leaf node with the greatest depth (rank) in
      # the error tree. The deepest leaf is the one furthest from root.
      #
      # @param node [Parsanol::Cause] current node in error tree
      # @param rank [Integer] current depth from root
      # @return [Array<Integer, Parsanol::Cause>] [depth, deepest_leaf]
      #
      def find_deepest_leaf(node, rank = 0)
        best_node = node
        best_rank = rank

        kids = node.children
        if kids && !kids.empty?
          kids.each do |kid|
            kid_rank, kid_node = find_deepest_leaf(kid, rank + 1)

            if kid_rank > best_rank
              best_rank = kid_rank
              best_node = kid_node
            end
          end
        end

        [best_rank, best_node]
      end
    end
  end
end
