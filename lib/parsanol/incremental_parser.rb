# frozen_string_literal: true

# Parsanol::IncrementalParser - Incremental Parser for Editor Integration
#
# Parse with support for incremental edits. This is useful for editor integration
# where the input changes frequently (e.g., as the user types).
#
# Usage:
#   parser = Parsanol::IncrementalParser.new(grammar, initial_text)
#
#   # When text changes
#   parser.apply_edit(start: 5, deleted: 3, inserted: "new")
#   result = parser.reparse
#
# Requires native extension for full functionality.

module Parsanol
  # Represents an edit to apply to the input
  class Edit
    attr_reader :start, :deleted, :inserted

    def initialize(start:, deleted:, inserted: '')
      @start = start
      @deleted = deleted
      @inserted = inserted
    end

    # Get the old range that was replaced
    def old_range
      @start...(@start + @deleted)
    end

    # Check if this edit affects a specific position
    def affects_position?(position)
      position >= @start && position < @start + @deleted + @inserted.length
    end

    # Get the new position after this edit
    def new_position
      @start + @inserted.length
    end

    # Apply this edit to a string
    def apply(input)
      input[0...@start] + @inserted + input[(@start + @deleted)..]
    end

    def to_s
      "Edit(#{@start}, +#{@inserted.length}, -#{@deleted})"
    end

    def ==(other)
      return false unless other.is_a?(Edit)

      @start == other.start && @deleted == other.deleted && @inserted == other.inserted
    end
  end

  class IncrementalParser
    # Create a new incremental parser
    #
    # @param grammar [Parsanol::Parser, Parsanol::Atoms::Base] Grammar to use
    # @param initial_input [String] Initial input string
    def initialize(grammar, initial_input = '')
      @grammar = grammar
      @input = initial_input

      if Parsanol::Native.available?
        grammar_json = Parsanol::Native.serialize_grammar(grammar.root)
        @native_parser = Parsanol::Native.incremental_parser_new(grammar_json, initial_input)
      else
        @native_parser = nil
      end

      @edits = []
      @cached_result = nil
    end

    # Apply an edit to the parser
    #
    # @param start [Integer] Start position of edit
    # @param deleted [Integer] Number of characters deleted
    # @param inserted [String] Text to insert
    def apply_edit(start:, deleted:, inserted: '')
      edit = Edit.new(start: start, deleted: deleted, inserted: inserted)
      @edits << edit

      # Update cached input
      @input = edit.apply(@input)

      # Invalidate cached result
      @cached_result = nil

      return unless @native_parser

      Parsanol::Native.incremental_parser_apply_edit(@native_parser, start, deleted, inserted)
    end

    # Convenience method to apply multiple edits
    #
    # @param edits [Array<Hash>] Array of {start:, deleted:, inserted:} hashes
    def apply_edits(edits)
      edits.each do |edit_hash|
        apply_edit(**edit_hash)
      end
    end

    # Reparse with current input (or optional new input)
    #
    # @param new_input [String, nil] Optional new input (replaces current)
    # @return [Object] Parse result
    def reparse(new_input = nil)
      if new_input
        @input = new_input
        @edits.clear
        @cached_result = nil
      end

      return @cached_result if @cached_result

      if @native_parser
        @cached_result = Parsanol::Native.incremental_parser_reparse(@native_parser, @input)
      else
        # Pure Ruby fallback - reparse from scratch
        root = @grammar.root
        @cached_result = root.parse(@input)
      end

      @cached_result
    end

    # Invalidate a range (for external changes)
    #
    # @param start [Integer] Start position
    # @param end_pos [Integer] End position
    def invalidate_range(_start, _end_pos)
      # Clear cached result if the invalidated range might affect it
      @cached_result = nil

      nil unless @native_parser
      # Native implementation handles invalidation
    end

    # Get the current input
    #
    # @return [String] Current input
    attr_reader :input

    # Get all applied edits
    #
    # @return [Array<Edit>] Array of edits
    def edits
      @edits.dup
    end

    # Check if there are unapplied edits
    #
    # @return [Boolean] True if there are pending edits
    def dirty?
      @cached_result.nil? && !@edits.empty?
    end

    # Reset to initial state
    #
    # @param new_input [String, nil] Optional new initial input
    def reset(new_input = nil)
      @input = new_input || ''
      @edits.clear
      @cached_result = nil

      return unless @native_parser && new_input

      grammar_json = Parsanol::Native.serialize_grammar(@grammar.root)
      @native_parser = Parsanol::Native.incremental_parser_new(grammar_json, @input)
    end
  end
end
