# frozen_string_literal: true

module Parsanol
  module ErrorReporter
    # Enhanced error reporter that uses contextual heuristics to provide
    # more relevant error messages. Builds on the Deepest reporter by adding
    # label tracking and intelligent error reset behavior.
    #
    # The key insight is that in a sequence of alternatives, the deepest error
    # from a branch that was partially successful is more meaningful than
    # errors from branches that failed immediately.
    #
    # @example Parser with labeled rules
    #   class MyParser < Parsanol::Parser
    #     rule(:expression, label: 'math expression') { ... }
    #     rule(:term, label: 'number or variable') { ... }
    #   end
    #
    #   # Error messages will include "while parsing math expression"
    #   # context when expression rule fails deep in parsing
    #
    # Inspired by contextual error reporting strategies in modern parsers.
    #
    class Contextual < Deepest
      # Creates a new contextual error reporter.
      #
      def initialize
        @prev_success_pos = 0
        clear_state
      end

      # Called when a sequence successfully matches. Resets error tracking
      # if this success is at or beyond the previous success position.
      # This ensures we keep errors from "partially successful" branches
      # rather than early failures in alternative choices.
      #
      # @param src [Parsanol::Source] input source
      # @return [nil]
      #
      def succ(src)
        current_pos = src.pos.bytepos
        # Only reset if we've made forward progress
        return if current_pos < @prev_success_pos

        @prev_success_pos = current_pos
        reset
        nil
      end

      # Clears all tracked state for a fresh start.
      #
      # @return [void]
      #
      def reset
        @deepest_cause = nil
        @active_label_pos = -1
        @active_label_text = nil
      end

      alias clear_state reset

      # Records an error and applies contextual labeling if the atom has one.
      # Delegates to parent class for deepest tracking.
      #
      # @param atom [Parsanol::Atoms::Base] atom that failed
      # @param src [Parsanol::Source] input source
      # @param msg [String, Array] error message
      # @param nested [Array, nil] child causes
      # @return [Parsanol::Cause] the error cause
      #
      def err(atom, src, msg, nested = nil)
        cause = super(atom, src, msg, nested)

        # Apply label if the atom has one
        if atom.respond_to?(:label) && (lbl = atom.label)
          maybe_update_label(lbl, src.pos.bytepos)
          cause.set_label(@active_label_text)
        end

        cause
      end

      # Updates the active context label if the new position is at or
      # beyond the current label position. This ensures we track the
      # label for the deepest/most specific failing construct.
      #
      # @param lbl [String] label text
      # @param byte_pos [Integer] position in input
      # @return [void]
      #
      def maybe_update_label(lbl, byte_pos)
        if byte_pos >= @active_label_pos
          @active_label_pos = byte_pos
          @active_label_text = lbl
        end
      end
    end
  end
end
