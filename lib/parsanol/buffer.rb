# frozen_string_literal: true

module Parsanol
  # A fixed-size buffer for efficient array operations.
  #
  # Buffer wraps an array with a logical size separate from capacity.
  # This allows reusing buffers without reallocating arrays, reducing GC pressure.
  #
  # == Usage
  #
  #   buffer = Buffer.new(capacity: 10)
  #   buffer.push("a")
  #   buffer.push("b")
  #   buffer.size  # => 2
  #   buffer.to_a  # => ["a", "b"]
  #   buffer.clear!
  #   buffer.size  # => 0 (but capacity still 10)
  #
  # == Size vs Capacity
  #
  # - Size: Number of elements logically in the buffer
  # - Capacity: Maximum elements before reallocation
  #
  # Reusing buffers maintains capacity while resetting size.
  #
  class Buffer
    include Resettable

    # @return [Integer] Logical size (number of elements)
    attr_reader :size

    # @return [Integer] Maximum capacity before growth
    attr_reader :capacity

    # @return [Array] Underlying array storage
    attr_reader :storage

    # Initialize a new buffer with specified capacity.
    #
    # @param capacity [Integer] Initial capacity (default: 10)
    #
    def initialize(capacity: 10)
      @capacity = capacity
      @storage = Array.new(capacity)
      @size = 0
    end

    # Add an element to the buffer.
    #
    # Grows buffer if needed, but this should be rare with proper size classes.
    #
    # @param element [Object] Element to add
    # @return [self] For method chaining
    #
    def push(element)
      grow! if @size >= @capacity
      @storage[@size] = element
      @size += 1
      self
    end

    alias << push

    # Get element at index.
    #
    # @param index [Integer] Zero-based index
    # @return [Object] Element at index, or nil if out of bounds
    #
    def [](index)
      return nil if index >= @size

      @storage[index]
    end

    # Set element at index.
    #
    # @param index [Integer] Zero-based index
    # @param value [Object] Value to set
    #
    def []=(index, value)
      @storage[index] = value if index < @size
    end

    # Convert buffer to array (creates new array slice of logical size).
    #
    # @return [Array] Array containing elements [0...size]
    #
    def to_a
      @storage[0...@size]
    end

    # Clear the buffer (reset logical size, keep capacity).
    #
    # @return [self] For method chaining
    #
    def clear!
      # Clear references for GC (keep capacity)
      @size.upto(@capacity - 1) { |i| @storage[i] = nil }
      @size = 0
      self
    end

    # Check if buffer is empty.
    #
    # @return [Boolean] true if size is zero
    #
    def empty?
      @size.zero?
    end

    # Reset protocol for ObjectPool compatibility.
    # Delegates to clear! for buffer cleanup.
    #
    # @return [self] For method chaining
    #
    def reset!
      clear!
    end

    private

    # Grow buffer capacity (double it).
    # Should be rare with proper size class selection.
    #
    def grow!
      new_capacity = @capacity * 2
      new_storage = Array.new(new_capacity)
      @storage.each_with_index { |elem, i| new_storage[i] = elem }
      @storage = new_storage
      @capacity = new_capacity
    end
  end
end
