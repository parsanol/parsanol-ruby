# frozen_string_literal: true

require_relative "../buffer"

module Parsanol
  module Pools
    # Manages fixed-size buffers organized by size class.
    #
    # BufferPool provides efficient buffer allocation by maintaining
    # separate pools for common buffer sizes. This reduces allocation
    # overhead and enables buffer reuse across parses.
    #
    # == Usage
    #
    #   pool = BufferPool.new
    #   buffer = pool.acquire(size: 8)  # Get buffer with capacity >= 8
    #   buffer.push("a")
    #   pool.release(buffer)
    #
    # == Size Classes
    #
    # Buffers are organized into size classes:
    # - Small: 2, 4, 8 (most common)
    # - Medium: 16, 32 (common)
    # - Large: 64+ (rare, allocated on demand)
    #
    # This matches typical parsing patterns where most arrays are small.
    #
    class BufferPool
      # Standard size classes (power of 2 for efficiency)
      SIZE_CLASSES = [2, 4, 8, 16, 32, 64].freeze

      # Default pool size per class
      DEFAULT_POOL_SIZE = 100

      # @return [Hash] Pools by size class
      attr_reader :pools

      # @return [Hash] Statistics per size class
      attr_reader :stats

      # Initialize a new BufferPool.
      #
      # @param pool_size [Integer] Number of buffers per size class
      #
      def initialize(pool_size: DEFAULT_POOL_SIZE)
        @pool_size = pool_size
        @pools = {}
        @stats = {}

        # Create pool for each size class
        SIZE_CLASSES.each do |size|
          @pools[size] = []
          @stats[size] = { created: 0, reused: 0, released: 0, discarded: 0 }
        end
      end

      # Acquire a buffer with at least the requested capacity.
      #
      # Returns a buffer from the appropriate size class pool.
      # If no buffer available, creates a new one.
      #
      # @param size [Integer] Minimum required capacity
      # @return [Buffer] Buffer with capacity >= size
      #
      def acquire(size:)
        size_class = select_size_class(size)

        # For non-standard size classes, create buffer on demand
        return Buffer.new(capacity: size_class) unless @pools.key?(size_class)

        pool = @pools[size_class]

        if pool.empty?
          @stats[size_class][:created] += 1
          Buffer.new(capacity: size_class)
        else
          @stats[size_class][:reused] += 1
          pool.pop
        end
      end

      # Release a buffer back to the pool.
      #
      # Clears the buffer and returns it to the appropriate size class pool.
      #
      # @param buffer [Buffer] Buffer to release
      # @return [Boolean] true if returned to pool, false if discarded
      #
      def release(buffer)
        size_class = buffer.capacity
        pool = @pools[size_class]

        # Discard if pool is full or size not in standard classes
        if !pool || pool.size >= @pool_size
          @stats[size_class][:discarded] += 1 if @stats[size_class]
          return false
        end

        buffer.clear!
        @stats[size_class][:released] += 1
        pool.push(buffer)
        true
      end

      # Get statistics for all size classes.
      #
      # @return [Hash] Statistics by size class
      #
      def statistics
        result = {}
        SIZE_CLASSES.each do |size|
          stats = @stats[size]
          total_acquires = stats[:created] + stats[:reused]
          utilization = if total_acquires.zero?
                          0.0
                        else
                          (stats[:reused].to_f / total_acquires * 100)
                        end

          result[size] = {
            available: @pools[size].size,
            created: stats[:created],
            reused: stats[:reused],
            released: stats[:released],
            discarded: stats[:discarded],
            utilization: utilization.round(2),
          }
        end
        result
      end

      # Clear all pools.
      #
      # @return [void]
      #
      def clear!
        @pools.each_value(&:clear)
        @stats.each_value do |s|
          s[:created] = s[:reused] = s[:released] = s[:discarded] = 0
        end
      end

      private

      # Select appropriate size class for requested size.
      #
      # Returns smallest size class >= requested size.
      #
      # @param size [Integer] Requested size
      # @return [Integer] Size class
      #
      def select_size_class(size)
        SIZE_CLASSES.find { |sc| sc >= size } || next_power_of_2(size)
      end

      # Find next power of 2 greater than or equal to n.
      #
      # @param n [Integer] Input value
      # @return [Integer] Next power of 2
      #
      def next_power_of_2(n)
        return 1 if n <= 0

        n -= 1
        n |= n >> 1
        n |= n >> 2
        n |= n >> 4
        n |= n >> 8
        n |= n >> 16
        n + 1
      end
    end
  end
end
