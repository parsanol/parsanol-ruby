# frozen_string_literal: true

# Parsanol::SourceLocation - Source Location Tracking
#
# Track source positions (line, column, offset) through the parsing and
# transformation pipeline. This is useful for error reporting, IDE integration,
# and source mapping.
#
# Usage:
#   # Parse with source tracking
#   result = parser.parse_with_spans("hello world")
#   tree = result.tree
#   spans = result.spans
#
#   # Access span for a node
#   span = spans[node_id]
#   puts "Matched at line #{span.start.line}, column #{span.start.column}"
#
# Requires native extension for full functionality.

module Parsanol
  # Represents a position in source code
  class SourcePosition
    attr_reader :offset, :line, :column

    def initialize(offset:, line:, column:)
      @offset = offset
      @line = line
      @column = column
    end

    def to_s
      "line #{@line}, column #{@column} (offset #{@offset})"
    end

    def to_h
      { offset: @offset, line: @line, column: @column }
    end

    def ==(other)
      return false unless other.is_a?(SourcePosition)

      @offset == other.offset && @line == other.line && @column == other.column
    end

    def eql?(other)
      self == other
    end

    def hash
      [@offset, @line, @column].hash
    end
  end

  # Represents a span in source code (from start to end position)
  class SourceSpan
    attr_reader :start, :end

    def initialize(start_pos:, end_pos:)
      @start = start_pos.is_a?(SourcePosition) ? start_pos : SourcePosition.new(**start_pos)
      @end = end_pos.is_a?(SourcePosition) ? end_pos : SourcePosition.new(**end_pos)
    end

    # Create a span from offsets (computes line/column from input)
    def self.from_offsets(input, start_offset, end_offset)
      start_pos = compute_position(input, start_offset)
      end_pos = compute_position(input, end_offset)
      new(start_pos: start_pos, end_pos: end_pos)
    end

    # Merge two spans (returns a new span covering both)
    def merge(other)
      return self if other.nil?

      SourceSpan.new(
        start_pos: [@start, other.start].min_by(&:offset),
        end_pos: [@end, other.end].max_by(&:offset)
      )
    end

    # Check if this span overlaps with another
    def overlaps?(other)
      return false if other.nil?

      @start.offset < other.end.offset && @end.offset > other.start.offset
    end

    # Check if this span is adjacent to another
    def adjacent?(other)
      return false if other.nil?

      @end.offset == other.start.offset || other.end.offset == @start.offset
    end

    # Check if a position is within this span
    def contains?(position)
      offset = position.is_a?(SourcePosition) ? position.offset : position
      offset.between?(@start.offset, @end.offset)
    end

    # Get the length of the span in bytes
    def length
      @end.offset - @start.offset
    end

    # Extract the source text from the input
    def extract(input)
      input.byteslice(@start.offset, length)
    end

    def to_s
      "#{@start} - #{@end}"
    end

    def to_h
      { start: @start.to_h, end: @end.to_h }
    end

    def ==(other)
      return false unless other.is_a?(SourceSpan)

      @start == other.start && @end == other.end
    end

    # Compute line and column from offset
    def self.compute_position(input, offset)
      line = 1
      column = 1
      current_offset = 0

      input.each_char do |char|
        break if current_offset >= offset

        if char == "\n"
          line += 1
          column = 1
        else
          column += 1
        end

        current_offset += 1
      end

      SourcePosition.new(offset: offset, line: line, column: column)
    end
  end

  # Result wrapper for parse_with_spans
  class ParseResultWithSpans
    attr_reader :tree, :spans

    def initialize(tree:, spans:)
      @tree = tree
      @spans = spans
    end

    # Get span for a specific node
    def span_for(node_id)
      @spans[node_id]
    end

    # Get all spans that contain a position
    def spans_at(offset)
      @spans.values.select { |span| span.contains?(offset) }
    end
  end
end
