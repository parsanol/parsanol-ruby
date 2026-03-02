# frozen_string_literal: true

module Parsanol
  module Pools
    # Specialized object pool for Position instances.
    #
    # PositionPool extends ObjectPool to provide position-specific behavior,
    # particularly managing the line and column state for reuse.
    #
    # == Usage
    #
    #   pool = Parsanol::Pools::PositionPool.new(size: 1000)
    #
    #   # Acquire a position with line/column
    #   pos = pool.acquire_with(string: "source", bytepos: 42, charpos: 42)
    #
    #   # Return to pool (automatically reset)
    #   pool.release(pos)
    #
    # == Architecture
    #
    # v3.0.0 uses integer positions during parsing for efficiency.
    # Position objects are only created when:
    # - Generating error messages (need line/column)
    # - Materializing error context
    #
    # By pooling Position objects, we reduce GC pressure at the
    # materialization point without changing the fast integer-based
    # parsing path.
    #
    class PositionPool < Parsanol::ObjectPool
      # Initialize a new PositionPool.
      #
      # @param size [Integer] Maximum number of Position objects to pool
      # @param preallocate [Boolean] Whether to pre-allocate positions
      #
      def initialize(size: 1000, preallocate: false)
        # NOTE: Position requires arguments, so we cannot pre-allocate
        super(Parsanol::Position, size: size, preallocate: false)
      end

      # Acquire a Position from the pool.
      # Overrides ObjectPool#acquire to handle Position's required arguments.
      #
      # @return [Parsanol::Position] A position instance from pool or newly created
      #
      def acquire
        if @available.empty?
          @stats[:created] += 1
          # Create Position with default values since it requires arguments
          Parsanol::Position.new('', 0, 0)
        else
          @stats[:reused] += 1
          @available.pop
        end
      end

      # Acquire a Position from the pool and initialize it with values.
      #
      # @param string [String] Source string for position tracking
      # @param bytepos [Integer] Byte position in source
      # @param charpos [Integer, nil] Character position (optional)
      # @return [Parsanol::Position] Initialized position from pool
      #
      def acquire_with(string:, bytepos:, charpos: nil)
        pos = acquire
        pos.reset!(string, bytepos, charpos)
        pos
      end

      # Return a position to the pool after resetting it.
      #
      # @param pos [Parsanol::Position] The position to return
      # @return [Boolean] true if returned to pool, false if discarded
      #
      def release(pos)
        # Don't pool if we're at capacity - discard instead
        if @available.size >= @size
          @stats[:discarded] += 1
          return false
        end

        # Reset position state with default values before returning to pool
        pos.reset!('', 0, 0)

        @stats[:released] += 1
        @available.push(pos)
        true
      end
    end
  end
end
