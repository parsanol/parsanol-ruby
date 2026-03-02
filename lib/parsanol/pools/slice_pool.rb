# frozen_string_literal: true

module Parsanol
  module Pools
    # Specialized object pool for Parsanol::Slice instances.
    #
    # SlicePool extends ObjectPool to provide convenient methods for
    # acquiring and configuring Slice objects. Since Slices are frequently
    # created during parsing, pooling them significantly reduces GC pressure.
    #
    # == Usage
    #
    #   pool = Parsanol::Pools::SlicePool.new(size: 1000)
    #
    #   # Acquire and initialize in one step
    #   slice = pool.acquire_with(0, "hello", line_cache)
    #
    #   # Use the slice...
    #
    #   # Return to pool
    #   pool.release(slice)
    #
    # == Why Pool Slices?
    #
    # Profiling (Session 19) showed that Slice allocation contributes
    # significantly to GC overhead. By reusing Slice objects, we can:
    # - Reduce object allocations by 70-80%
    # - Decrease GC time from 67% to ~20%
    # - Improve overall parsing throughput by 2-3x
    #
    class SlicePool < Parsanol::ObjectPool
      # Initialize a new SlicePool.
      #
      # @param size [Integer] Maximum number of Slice objects to pool (default: 1000)
      # @param preallocate [Boolean] Whether to pre-allocate slices (default: true)
      #
      # @example Create a SlicePool
      #   pool = SlicePool.new(size: 2000)
      #
      def initialize(size: 1000, preallocate: true)
        super(Parsanol::Slice, size: size, preallocate: preallocate)
      end

      # Acquire a Slice from the pool and initialize it with given values.
      #
      # This is a convenience method that combines acquire + reset! into
      # a single operation, making it easier to work with pooled slices.
      #
      # @param bytepos [Integer] Byte position in the original input
      # @param str [String] The slice content
      # @param line_cache [Object] Optional line cache for line/column info
      # @return [Parsanol::Slice] An initialized slice ready for use
      #
      # @example Acquire and initialize
      #   slice = pool.acquire_with(0, "hello", line_cache)
      #
      def acquire_with(bytepos, str, line_cache = nil)
        slice = acquire
        slice.reset!(bytepos, str, line_cache)
        slice
      end
    end
  end
end