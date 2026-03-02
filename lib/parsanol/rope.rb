# frozen_string_literal: true

module Parsanol
  # Rope data structure for efficient string accumulation.
  #
  # Uses deferred concatenation to avoid O(n²) repeated string building.
  # Segments are accumulated in O(1) time and joined once in O(n) time when
  # converted to a final string.
  #
  # @example Basic usage
  #   rope = Rope.new
  #   rope.append('hello')
  #   rope.append(' ')
  #   rope.append('world')
  #   rope.to_s  # => "hello world"
  #
  # @example With Slices
  #   rope = Rope.new
  #   rope.append(Slice.new(0, 'hello'))
  #   rope.append(Slice.new(5, ' world'))
  #   rope.to_s  # => "hello world"
  #
  class Rope
    # Creates a new empty Rope.
    def initialize
      @segments = []
      @frozen = false
    end

    # Appends a string or Slice to the rope.
    #
    # This is an O(1) operation. The segment is stored as-is and will be
    # joined later when {#to_s} is called.
    #
    # @param segment [String, Slice] The segment to append
    # @return [Rope] self for method chaining
    # @raise [FrozenError] if rope has been frozen by calling {#to_s}
    def append(segment)
      raise FrozenError, "can't modify frozen Rope" if @frozen

      @segments << segment
      self
    end

    # Converts the rope to a final string.
    #
    # This is an O(n) operation performed once. After calling this method,
    # the rope is frozen and cannot be modified further.
    #
    # @return [String] The concatenated result of all segments
    def to_s
      @frozen = true
      @segments.join
    end

    # Checks if the rope is empty (contains no segments).
    #
    # @return [Boolean] true if no segments have been appended
    def empty?
      @segments.empty?
    end

    # Estimates the total size of all segments.
    #
    # This is an estimate because segments may be Slice objects or other
    # types that respond to #size or #to_s.
    #
    # @return [Integer] The sum of all segment sizes
    def size
      @segments.sum { |s| s.respond_to?(:size) ? s.size : s.to_s.size }
    end

    # Creates a rope from an existing string.
    #
    # @param str [String] The string to initialize the rope with
    # @return [Rope] A new rope containing the string
    def self.from_string(str)
      new.tap { |r| r.append(str) unless str.empty? }
    end
  end
end
