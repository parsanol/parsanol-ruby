# frozen_string_literal: true

require "stringio"
require "strscan"

require "parsanol/position"
require "parsanol/source/line_cache"
require "parsanol/pools/slice_pool"
require "parsanol/pools/position_pool"

module Parsanol
  # Encapsulates input source for parsing operations. Provides position tracking,
  # character consumption, line/column calculation, and object pooling for
  # memory efficiency.
  #
  # @example Creating a source
  #   src = Parsanol::Source.new("input string")
  #   src.matches?(/a/)  # => true if 'a' is at current position
  #   src.consume(1)     # => Slice containing one character
  #
  # Inspired by source/position tracking patterns in parser implementations.
  #
  class Source
    # @return [Parsanol::Pools::SlicePool] pool for Slice objects
    attr_reader :slice_pool

    # @return [Parsanol::Pools::PositionPool] pool for Position objects
    attr_reader :position_pool

    # Creates a new source wrapper around a string.
    #
    # @param input [#to_str] string-like object to parse
    # @raise [ArgumentError] if input doesn't respond to to_str
    #
    def initialize(input)
      unless input.respond_to?(:to_str)
        raise ArgumentError,
              "Source requires a string-like object (responds to to_str)"
      end

      # Core scanner for input traversal
      @scanner = StringScanner.new(input)
      @raw_string = input.to_str

      # Regex cache: maps count n to /(.|$){n}/m pattern
      @regex_cache = Hash.new do |h, count|
        h[count] = Regexp.new("(.|$){#{count}}", Regexp::MULTILINE)
      end

      # Line ending cache for position-to-line/column mapping
      @line_data = LineCache.new
      @line_data.scan_for_line_endings(0, input)

      # Object pools for memory efficiency
      # SlicePool: reduces Slice allocations during matching
      @slice_pool = Parsanol::Pools::SlicePool.new(size: 5000)

      # PositionPool: reduces Position allocations for error reporting
      @position_pool = Parsanol::Pools::PositionPool.new(size: 1000)
    end

    # Checks if a pattern matches at the current input position without consuming.
    #
    # @param pattern [Regexp] pattern to test
    # @return [Boolean] true if pattern matches at current position
    #
    def matches?(pattern)
      @scanner.match?(pattern)
    end
    alias match matches?

    # Consumes n characters from input and returns them as a pooled Slice.
    #
    # @param count [Integer] number of characters to consume
    # @return [Parsanol::Slice] slice containing consumed characters
    #
    def consume(count)
      current_pos = @scanner.pos
      content = @scanner.scan(@regex_cache[count])
      @slice_pool.acquire_with(current_pos, content, @line_data)
    end

    # Creates a pooled slice at a specific position.
    # Preferred method for atoms to construct slices.
    #
    # @param offset [Integer] byte position in source
    # @param content [String] slice content
    # @return [Parsanol::Slice] pooled slice instance
    #
    def slice(offset, content)
      @slice_pool.acquire_with(offset, content, @line_data)
    end

    # Returns a slice to the pool for reuse.
    #
    # @param sl [Parsanol::Slice] slice to release
    #
    def release_slice(sl)
      @slice_pool.release(sl)
    end

    # Returns count of remaining characters in input.
    #
    # @return [Integer] characters left to consume
    #
    def chars_left
      @scanner.rest_size
    end

    # Counts characters from current position until a target string.
    # Returns chars_left if target is not found.
    #
    # @param target [String] string to search for
    # @return [Integer] count of chars until target or remaining chars
    #
    def chars_until(target)
      found = @scanner.check_until(Regexp.new(Regexp.escape(target)))
      return chars_left unless found

      found.size - target.size
    end

    # Finds the byte position of the next occurrence of a character.
    # Does not move the scanner position.
    #
    # @param ch [String] character to search for
    # @return [Integer, nil] byte position or nil if not found
    #
    def index_of_char(ch)
      rel_idx = @scanner.rest.index(ch)
      return nil unless rel_idx

      @scanner.pos + rel_idx
    end

    # Returns current byte position in input.
    #
    # @return [Integer] current byte offset
    # @note Encoding-aware: position is in bytes, not characters
    #
    def pos
      @scanner.pos
    end
    alias bytepos pos

    # Sets the current byte position.
    #
    # @param new_pos [Integer] target byte position
    #
    def bytepos=(new_pos)
      @scanner.pos = new_pos
    rescue RangeError
      # Silently ignore out-of-range positions
    end

    # Converts a byte position to line and column numbers.
    #
    # @param offset [Integer, nil] byte position (defaults to current)
    # @return [Array<Integer, Integer>] [line, column] tuple (1-indexed)
    #
    def line_and_column(offset = nil)
      effective = offset || @scanner.pos
      @line_data.line_and_column(effective)
    end

    # Creates a pooled Position object for error reporting.
    #
    # @param offset [Integer, nil] byte position (defaults to current)
    # @return [Parsanol::Position] pooled position instance
    #
    def position(offset = nil)
      effective = offset || @scanner.pos
      line_and_column(effective)

      # Character position approximation
      char_pos = @raw_string.byteslice(0, effective).size

      @position_pool.acquire_with(
        string: @raw_string,
        bytepos: effective,
        charpos: char_pos,
      )
    end
  end
end
