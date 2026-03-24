# frozen_string_literal: true

module Parsanol
  # Zero-copy string view that references original input.
  #
  # StringView avoids string copies by maintaining a reference to the
  # original string with offset and length. Strings are only materialized
  # when explicitly requested via #to_s.
  #
  # == Usage
  #
  #   view = StringView.new(input_string, offset: 10, length: 5)
  #   view.to_s  # Materializes string only when needed
  #   view[0]    # Direct character access without copying
  #
  # == Performance
  #
  # - No string allocation until to_s called
  # - Direct character access without copying
  # - Reduced GC pressure from intermediate strings
  # - Caches materialized strings for reuse
  #
  # == Design Principles
  #
  # 1. Zero-Copy: Reference original string, don't copy
  # 2. Lazy Materialization: Create strings only when to_s called
  # 3. Caching: Cache materialized strings for reuse
  # 4. Compatibility: Acts like String where needed
  # 5. Extensibility: Foundation for Rope (Phase 3.2)
  #
  class StringView
    include Resettable

    # @return [String] Original input string
    attr_reader :string

    # @return [Integer] Byte offset into string
    attr_reader :offset

    # @return [Integer] Length in bytes
    attr_reader :length

    # Initialize a new StringView.
    #
    # @param string [String] Original input string
    # @param offset [Integer] Byte offset (default: 0)
    # @param length [Integer] Length in bytes (default: string.bytesize)
    #
    def initialize(string, offset: 0, length: nil)
      @string = string
      @offset = offset
      @length = length || (string.bytesize - offset)
      @materialized = nil
    end

    # Materialize to string (with caching).
    #
    # First call creates string slice, subsequent calls return cached.
    # This implements lazy evaluation - strings are only created when
    # explicitly needed, not during parsing.
    #
    # @return [String] Materialized string
    #
    def to_s
      @materialized ||= @string.byteslice(@offset, @length)
    end

    # Get character at index (zero-copy).
    #
    # Direct access to character in original string without creating
    # intermediate string objects.
    #
    # @param index [Integer] Zero-based index
    # @return [String, nil] Character at index or nil
    #
    def [](index)
      return nil if index.negative? || index >= @length

      @string.byteslice(@offset + index, 1)
    end

    # Get byte size.
    #
    # @return [Integer] Length in bytes
    #
    def bytesize
      @length
    end

    alias size bytesize
    alias length bytesize

    # Check if empty.
    #
    # @return [Boolean] true if length is 0
    #
    def empty?
      @length.zero?
    end

    # Compare with another object.
    #
    # StringViews are only equal if they reference the exact same string object
    # (by object_id) and have the same offset/length. This is consistent with
    # the view pattern - they're views of a specific string instance.
    #
    # When comparing with a String, content is compared.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if equal
    #
    def ==(other)
      case other
      when String
        to_s == other
      when StringView
        # Only equal if viewing the exact same string object with same range
        @string.equal?(other.string) &&
          @offset == other.offset &&
          @length == other.length
      else
        super
      end
    end

    alias eql? ==

    # Hash code for hashing.
    #
    # Uses object_id of string to avoid materializing the view.
    #
    # @return [Integer] Hash code
    #
    def hash
      [@string.object_id, @offset, @length].hash
    end

    # Create substring view (zero-copy).
    #
    # Returns a new StringView referencing a substring of this view.
    # No string allocation occurs - just a new view with adjusted offset.
    #
    # @param start [Integer] Start offset (relative to view)
    # @param len [Integer] Length
    # @return [StringView] New view of substring
    #
    def slice(start, len)
      # Handle edge cases
      if len <= 0 || start >= @length
        return self.class.new(@string, offset: @offset,
                                       length: 0)
      end

      # Clamp start to valid range [0, @length)
      clamped_start = [[start, 0].max, @length].min

      # Calculate actual offset in original string
      actual_offset = @offset + clamped_start

      # Calculate actual length (min of requested and available)
      available = @length - clamped_start
      actual_length = [len, available].min

      self.class.new(@string, offset: actual_offset, length: actual_length)
    end

    # Inspect for debugging.
    #
    # Shows whether string has been materialized.
    #
    # @return [String] Inspection string
    #
    def inspect
      if @materialized
        "#<StringView:#{object_id} @offset=#{@offset} @length=#{@length} cached=#{@materialized.inspect}>"
      else
        "#<StringView:#{object_id} @offset=#{@offset} @length=#{@length}>"
      end
    end

    # Reset for pooling (if needed in future phases).
    #
    # Allows StringView objects to be reused from a pool.
    #
    # @param string [String] New string
    # @param offset [Integer] New offset
    # @param length [Integer] New length
    # @return [self]
    #
    def reset!(string, offset, length)
      @string = string
      @offset = offset
      @length = length
      @materialized = nil
      self
    end
  end
end
