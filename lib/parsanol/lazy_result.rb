# frozen_string_literal: true

module Parsanol
  # Lazy wrapper around Buffer that defers array materialization.
  #
  # LazyResult wraps a Buffer and only creates an Array when the result
  # is actually accessed. This reduces allocations for results that are
  # never used (cache hits, backtracking, etc.).
  #
  # == Usage
  #
  #   lazy = LazyResult.new(buffer, context)
  #   # No array allocated yet
  #
  #   lazy.to_a  # Now array is materialized and cached
  #   lazy.to_a  # Returns cached array
  #
  # == Transparency
  #
  # LazyResult acts like an Array for most operations:
  # - Enumerable methods work (each, map, select, etc.)
  # - Array access works ([], size, empty?, etc.)
  # - Can be used in transforms without changes
  #
  class LazyResult
    # @return [Buffer] The underlying buffer
    attr_reader :buffer

    # @return [Context] The context (for buffer release)
    attr_reader :context

    # @return [Array, nil] Cached materialized array
    attr_reader :materialized

    # Initialize a new LazyResult.
    #
    # @param buffer [Buffer] Buffer containing elements
    # @param context [Context] Context for buffer management
    #
    def initialize(buffer, context)
      @buffer = buffer
      @context = context
      @materialized = nil
    end

    # Materialize to array (with caching).
    #
    # First call creates array from buffer, subsequent calls return cached.
    #
    # @return [Array] Materialized array
    #
    def to_a
      @materialized ||= @buffer.to_a
    end

    # Get element at index (materializes if needed).
    #
    # @param index [Integer] Zero-based index
    # @return [Object] Element at index
    #
    def [](index)
      to_a[index]
    end

    # Get number of elements.
    #
    # @return [Integer] Number of elements
    #
    def size
      @buffer.size
    end

    alias length size

    # Check if empty.
    #
    # @return [Boolean] true if no elements
    #
    def empty?
      @buffer.empty?
    end

    # Iterate over elements (materializes if needed).
    #
    # @yield [element] Each element
    # @return [Enumerator, self] Enumerator if no block, self otherwise
    #
    def each(&)
      return to_enum(:each) unless block_given?

      to_a.each(&)
      self
    end

    # Check if acts like an array.
    #
    # @param other [Class] Class to check against
    # @return [Boolean] true if Array
    #
    def is_a?(other)
      other == Array || super
    end

    alias kind_of? is_a?

    # Respond to array methods.
    #
    # @param method [Symbol] Method name
    # @param include_private [Boolean] Include private methods
    # @return [Boolean] true if responds
    #
    def respond_to?(method, include_private = false)
      super || to_a.respond_to?(method, include_private)
    end

    # Delegate unknown methods to materialized array.
    #
    # @param method [Symbol] Method name
    # @param args [Array] Arguments
    # @param block [Proc] Block if given
    # @return [Object] Result of method call
    #
    def method_missing(method, ...)
      if to_a.respond_to?(method)
        to_a.public_send(method, ...)
      else
        super
      end
    end

    # Support respond_to_missing? for proper method_missing implementation.
    #
    # @param method [Symbol] Method name
    # @param include_private [Boolean] Include private methods
    # @return [Boolean] true if method is supported
    #
    def respond_to_missing?(method, include_private = false)
      to_a.respond_to?(method, include_private) || super
    end

    # Compare with another object.
    # LazyResult compares equal to arrays with the same content.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if equal
    #
    def ==(other)
      if other.is_a?(Array)
        to_a == other
      elsif other.is_a?(LazyResult)
        to_a == other.to_a
      else
        super
      end
    end

    alias eql? ==

    # Hash code based on materialized array.
    #
    # @return [Integer] Hash code
    #
    def hash
      to_a.hash
    end

    # Inspect for debugging.
    #
    # @return [String] Inspection string
    #
    def inspect
      if @materialized
        "#<LazyResult:#{object_id} materialized=#{@materialized.inspect}>"
      else
        "#<LazyResult:#{object_id} buffer.size=#{@buffer.size}>"
      end
    end
  end
end
