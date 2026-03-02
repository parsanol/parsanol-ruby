# frozen_string_literal: true

module Parsanol
  module Pools
    # Specialized object pool for Array instances.
    #
    # ArrayPool extends ObjectPool to provide array-specific behavior,
    # particularly ensuring arrays are cleared before being returned to
    # the pool for reuse.
    #
    # == Usage
    #
    #   pool = Parsanol::Pools::ArrayPool.new(size: 1000)
    #
    #   # Acquire an array
    #   array = pool.acquire
    #   array << 'item1'
    #   array << 'item2'
    #
    #   # Return to pool (automatically cleared)
    #   pool.release(array)
    #
    #   # Next acquire gets a clean, empty array
    #   array2 = pool.acquire
    #   array2.empty? # => true
    #
    # == Why Pool Arrays?
    #
    # Profiling (Session 19) showed that array allocations account for
    # 74% of memory usage during parsing. Temporary arrays used for:
    # - Collecting repetition results
    # - Building sequence results
    # - Accumulating alternative matches
    #
    # By pooling arrays, we can:
    # - Reduce array allocations by 60-70%
    # - Decrease memory pressure
    # - Improve overall parsing performance
    #
    class ArrayPool < Parsanol::ObjectPool
      # Initialize a new ArrayPool.
      #
      # @param size [Integer] Maximum number of Arrays to pool (default: 1000)
      # @param preallocate [Boolean] Whether to pre-allocate arrays (default: true)
      #
      # @example Create an ArrayPool
      #   pool = ArrayPool.new(size: 2000)
      #
      def initialize(size: 1000, preallocate: true)
        super(Array, size: size, preallocate: preallocate)
      end

      # Return an array to the pool after clearing its contents.
      #
      # This override ensures arrays are always empty when returned to
      # the pool, preventing stale data from polluting future uses.
      #
      # @param array [Array] The array to return to the pool
      # @return [Boolean] true if returned to pool, false if discarded
      #
      # @example Release with automatic clearing
      #   array = pool.acquire
      #   array << 1 << 2 << 3
      #   pool.release(array)
      #   # Array is now cleared and back in pool
      #
      def release(array)
        # Clear array before pooling to prevent stale data
        # Note: Array#clear is more efficient than array = []
        array.clear
        super(array)
      end
    end
  end
end