# frozen_string_literal: true

module Parsanol
  # Generic object pool for reducing garbage collection pressure.
  #
  # The ObjectPool class implements a simple object pooling strategy:
  # - Objects are pre-allocated on initialization
  # - Objects are reused instead of created new
  # - Objects are reset before being returned to the pool
  # - Pool size is bounded to prevent unbounded growth
  #
  # This reduces GC pressure by reusing objects instead of constantly
  # creating and destroying them, which is particularly beneficial for
  # frequently allocated objects like Slice instances.
  #
  # == Thread Safety
  #
  # This implementation is NOT thread-safe. If thread safety is required,
  # wrap pool operations in a mutex or use thread-local pools.
  #
  # == Usage Example
  #
  #   # Create a pool for Slice objects
  #   pool = Parsanol::ObjectPool.new(Parsanol::Slice, size: 1000)
  #
  #   # Acquire an object from the pool
  #   slice = pool.acquire
  #   slice.instance_variable_set(:@bytepos, 0)
  #   slice.instance_variable_set(:@str, "hello")
  #
  #   # Use the slice...
  #
  #   # Return it to the pool for reuse
  #   pool.release(slice)
  #
  # == Object Reset Protocol
  #
  # Objects returned to the pool will have their reset! method called
  # if they respond to it. This allows objects to clean up their state
  # before being reused. If reset! is not defined, the object is still
  # pooled but without automatic cleanup.
  #
  class ObjectPool
    # @return [Integer] Maximum number of objects to keep in the pool
    attr_reader :size

    # @return [Hash] Statistics about pool usage
    attr_reader :stats

    # Initialize a new object pool.
    #
    # @param klass [Class] The class of objects to pool
    # @param size [Integer] Maximum number of objects to keep in pool (default: 1000)
    # @param preallocate [Boolean] Whether to pre-allocate objects on initialization (default: true)
    #
    # @example Create a pool with default settings
    #   pool = ObjectPool.new(Array, size: 1000)
    #
    # @example Create a pool without pre-allocation
    #   pool = ObjectPool.new(Array, size: 1000, preallocate: false)
    #
    def initialize(klass, size: 1000, preallocate: true)
      @klass = klass
      @size = size
      @available = []
      @stats = {
        created: 0,
        reused: 0,
        released: 0,
        discarded: 0
      }

      # Pre-allocate objects for efficiency if requested
      # This reduces allocation overhead during initial parsing
      preallocate(size) if preallocate && can_preallocate?
    end

    # Acquire an object from the pool.
    #
    # If the pool has available objects, one is returned (and considered "reused").
    # If the pool is empty, a new object is created (and considered "created").
    #
    # @return [Object] An object instance from the pool or newly created
    #
    # @example Acquire from pool
    #   obj = pool.acquire
    #
    def acquire
      if @available.empty?
        @stats[:created] += 1
        @klass.new
      else
        @stats[:reused] += 1
        @available.pop
      end
    end

    # Return an object to the pool for reuse.
    #
    # Before returning to the pool:
    # 1. If object responds to reset!, that method is called to clean up state
    # 2. If pool is at capacity, the object is discarded instead of pooled
    #
    # This ensures:
    # - Objects are cleaned before reuse (no stale state)
    # - Pool doesn't grow unbounded (respects size limit)
    #
    # @param obj [Object] The object to return to the pool
    # @return [Boolean] true if object was returned to pool, false if discarded
    #
    # @example Return object to pool
    #   pool.release(obj)
    #
    def release(obj)
      # Don't pool if we're at capacity - discard instead
      if @available.size >= @size
        @stats[:discarded] += 1
        return false
      end

      # Reset object state if it supports the protocol
      obj.reset! if obj.respond_to?(:reset!)

      @stats[:released] += 1
      @available.push(obj)
      true
    end

    # Get current pool statistics.
    #
    # Statistics include:
    # - size: Maximum pool capacity
    # - available: Number of objects currently available in pool
    # - created: Total number of new objects created
    # - reused: Total number of times objects were reused from pool
    # - released: Total number of objects returned to pool
    # - discarded: Total number of objects discarded (pool was full)
    # - utilization: Percentage of acquires that were reused (0-100)
    #
    # @return [Hash] Hash containing pool statistics
    #
    # @example Get statistics
    #   stats = pool.stats
    #   puts "Pool utilization: #{stats[:utilization]}%"
    #
    def statistics
      total_acquires = @stats[:created] + @stats[:reused]
      utilization = total_acquires.zero? ? 0.0 : (@stats[:reused].to_f / total_acquires * 100)

      {
        size: @size,
        available: @available.size,
        created: @stats[:created],
        reused: @stats[:reused],
        released: @stats[:released],
        discarded: @stats[:discarded],
        utilization: utilization.round(2)
      }
    end

    # Clear all objects from the pool.
    #
    # This removes all pooled objects and resets statistics.
    # Useful for testing or when you want to force fresh allocations.
    #
    # @return [void]
    #
    # @example Clear the pool
    #   pool.clear!
    #
    def clear!
      @available.clear
      @stats = {
        created: 0,
        reused: 0,
        released: 0,
        discarded: 0
      }
    end

    private

    # Check if the pooled class can be pre-allocated.
    #
    # Some classes require arguments to initialize and cannot be
    # pre-allocated without those arguments. This method checks if
    # the class has a zero-arity initialize method.
    #
    # @return [Boolean] true if class can be instantiated without arguments
    #
    def can_preallocate?
      # Check if the class can be instantiated without arguments
      # This is a heuristic - we try to create one instance to test
      begin
        @klass.new
        true
      rescue ArgumentError
        # Class requires arguments, cannot pre-allocate
        false
      end
    end

    # Pre-allocate objects to fill the pool.
    #
    # This is called during initialization if preallocate: true is set.
    # Pre-allocation reduces allocation overhead during initial parsing.
    #
    # @param count [Integer] Number of objects to pre-allocate
    # @return [void]
    #
    def preallocate(count)
      count.times do
        @available.push(@klass.new)
      end
      # Adjust stats to reflect pre-allocation as "released" not "created"
      # since these objects haven't been acquired yet
      @stats[:released] = count
    end
  end
end