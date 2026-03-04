# frozen_string_literal: true

# Source position tracker for parsed content.
# Preserves both the string value and its byte offset in the original input,
# enabling precise error reporting and source mapping.
#
# Inspired by string slicing concepts in text editors and IDEs.
module Parsanol
  class Slice
    include Parsanol::Resettable

    attr_reader :content, :position_cache

    # Creates a slice with position tracking.
    #
    # @param byte_offset [Integer] position in original input
    # @param string_content [String] the slice content
    # @param cache [Object] optional cache for line/column lookup
    def initialize(byte_offset = 0, string_content = '', cache = nil)
      @byte_position = byte_offset
      @content = string_content
      @position_cache = cache
    end

    # Resets slice state for object pool reuse.
    #
    # @param new_offset [Integer] new byte position
    # @param new_content [String] new content
    # @param new_cache [Object] new line cache
    # @return [self] for method chaining
    def reset!(new_offset = 0, new_content = '', new_cache = nil)
      @byte_position = new_offset
      @content = new_content
      @position_cache = new_cache
      self
    end

    # Creates a Slice from a Rope concatenation.
    #
    # @param rope [Parsanol::Rope] rope to convert
    # @param offset [Integer] byte position
    # @param cache [Object] optional cache
    # @return [Parsanol::Slice] new slice
    def self.from_rope(rope, offset, cache = nil)
      new(offset, rope.to_s, cache)
    end

    # @return [Integer] byte offset in original input
    def offset
      @byte_position
    end

    alias bytepos offset
    alias charpos offset
    alias str content # backward compatibility
    alias line_cache position_cache # backward compatibility

    # Compares slices or strings for equality.
    #
    # @param other [Object] object to compare
    # @return [Boolean] true if equal
    def ==(other)
      return content == other if other.is_a?(String)
      return content == other.content if other.is_a?(Parsanol::Slice)

      content == other
    end

    # Type-strict equality check.
    #
    # @param other [Object] object to compare
    # @return [Boolean] true if same type and content
    def eql?(other)
      other.is_a?(Parsanol::Slice) && content.eql?(other.content)
    end

    # Hash for use as hash keys.
    #
    # @return [Integer] hash combining content and position
    def hash
      [content, offset].hash
    end

    # Matches regular expression against content.
    #
    # @param pattern [Regexp] pattern to match
    # @return [MatchData, nil] match result
    def match(pattern)
      content.match(pattern)
    end

    # @return [Integer] length of slice content
    def size
      content.size
    end

    alias length size

    # Concatenates slices assuming second continues from first's end.
    #
    # @param other [Slice, String] slice to append
    # @return [Parsanol::Slice] combined slice
    def +(other)
      self.class.new(@byte_position, content + other.to_s, position_cache)
    end

    # Returns [line, column] tuple for this position.
    #
    # @return [Array<Integer, Integer>] line and column (1-indexed)
    # @raise [ArgumentError] if no line cache available
    def line_and_column
      raise ArgumentError, 'Line/column info requires a line cache. Pass one during parsing.' unless position_cache

      position_cache.line_and_column(@byte_position)
    end

    # String conversions ---------------------------------------------------------

    def to_str
      content.is_a?(String) ? content : content.to_s
    end
    alias to_s to_str

    def to_slice
      self
    end

    def to_sym
      content.to_sym
    end

    def to_i
      content.to_i
    end

    def to_f
      content.to_f
    end

    # Inspection ---------------------------------------------------------

    def inspect
      "#{content.inspect}@#{offset}"
    end

    # JSON serialization --------------------------------------------------------

    # JSON serialization returns the full object with position info.
    # This is the default behavior - position info is ALWAYS included.
    #
    # @return [String] JSON representation with value and position
    def to_json(*)
      as_json.to_json(*)
    end

    # Returns a hash with full position information for JSON serialization.
    # Line and column are always included when a position cache is available.
    #
    # @return [Hash] hash with value, offset, length, and line/column
    def as_json(_options = {})
      result = {
        'value' => content,
        'offset' => offset,
        'length' => length
      }

      if position_cache
        line, column = line_and_column
        result['line'] = line
        result['column'] = column
      end

      result
    end

    # Returns a SourceSpan representing this slice's position
    #
    # @param input [String, nil] the original input (needed for line/column)
    # @return [Parsanol::SourceSpan] span object
    def to_span(_input = nil)
      start_pos = if position_cache
                    line, column = line_and_column
                    SourcePosition.new(offset: offset, line: line, column: column)
                  else
                    SourcePosition.new(offset: offset, line: 1, column: 1)
                  end

      end_offset = offset + length
      end_pos = if position_cache
                  line, column = position_cache.line_and_column(end_offset)
                  SourcePosition.new(offset: end_offset, line: line, column: column)
                else
                  SourcePosition.new(offset: end_offset, line: 1, column: 1)
                end

      SourceSpan.new(start_pos: start_pos, end_pos: end_pos)
    end

    # Extract this slice's content from the original input string
    #
    # @param input [String] the original input string
    # @return [String] the slice content extracted from input
    def extract_from(input)
      input.byteslice(offset, length)
    end
  end
end
