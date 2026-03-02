# frozen_string_literal: true

module Parsanol
  # Base class for efficient result construction.
  #
  # ResultBuilder provides specialized construction patterns that avoid
  # intermediate array allocations by building results directly.
  #
  # == Usage
  #
  #   builder = ResultBuilder.for(:repetition, context, estimated_size: 10)
  #   builder.add_element(value1)
  #   builder.add_element(value2)
  #   result = builder.build  # Returns LazyResult
  #
  # == Builders
  #
  # - RepetitionBuilder: For repetition results
  # - SequenceBuilder: For sequence results
  # - HashBuilder: For named capture results
  #
  class ResultBuilder
    # Factory method to create appropriate builder.
    #
    # @param type [Symbol] Builder type (:repetition, :sequence, :hash)
    # @param context [Context] Parse context
    # @param options [Hash] Builder options
    # @return [ResultBuilder] Appropriate builder instance
    #
    def self.for(type, context, **options)
      case type
      when :repetition
        RepetitionBuilder.new(context, **options)
      when :sequence
        SequenceBuilder.new(context, **options)
      when :hash
        HashBuilder.new(context, **options)
      else
        raise ArgumentError, "Unknown builder type: #{type}"
      end
    end

    # Initialize builder.
    #
    # @param context [Context] Parse context for buffer access
    #
    def initialize(context)
      @context = context
    end

    # Add element to result (subclasses implement).
    #
    # @param value [Object] Value to add
    # @return [self] For method chaining
    #
    def add_element(value)
      raise NotImplementedError
    end

    # Build final result (subclasses implement).
    #
    # @return [Object] Constructed result
    #
    def build
      raise NotImplementedError
    end

    # Release resources (subclasses implement).
    #
    # @return [void]
    #
    def release
      # Default: no-op
    end
  end

  # Builder for repetition results.
  #
  # Constructs [:repetition, ...] arrays efficiently.
  #
  class RepetitionBuilder < ResultBuilder
    # Initialize repetition builder.
    #
    # @param context [Context] Parse context
    # @param tag [Symbol] Tag to use (default: :repetition)
    # @param estimated_size [Integer] Estimated element count
    #
    def initialize(context, tag: :repetition, estimated_size: 10)
      super(context)
      @tag = tag
      @buffer = context.acquire_buffer(size: estimated_size + 1)
      @buffer.push(@tag)
    end

    # Add element to repetition.
    #
    # @param value [Object] Element to add
    # @return [self]
    #
    def add_element(value)
      @buffer.push(value)
      self
    end

    # Build LazyResult.
    #
    # @return [LazyResult] Lazy repetition result
    #
    def build
      Parsanol::LazyResult.new(@buffer, @context)
    end

    # Release buffer on failure.
    #
    # @return [void]
    #
    def release
      @context.release_buffer(@buffer) if @buffer
      @buffer = nil
    end
  end

  # Builder for sequence results.
  #
  # Constructs [:sequence, ...] arrays efficiently.
  #
  class SequenceBuilder < ResultBuilder
    # Initialize sequence builder.
    #
    # @param context [Context] Parse context
    # @param size [Integer] Expected sequence length
    #
    def initialize(context, size: 5)
      super(context)
      @buffer = context.acquire_buffer(size: size + 1)
      @buffer.push(:sequence)
    end

    # Add element to sequence.
    #
    # @param value [Object] Element to add
    # @return [self]
    #
    def add_element(value)
      @buffer.push(value) if value  # Skip nil values
      self
    end

    # Build LazyResult.
    #
    # @return [LazyResult] Lazy sequence result
    #
    def build
      Parsanol::LazyResult.new(@buffer, @context)
    end

    # Release buffer on failure.
    #
    # @return [void]
    #
    def release
      @context.release_buffer(@buffer) if @buffer
      @buffer = nil
    end
  end

  # Builder for hash results (named captures).
  #
  # Constructs hashes directly without intermediate arrays.
  #
  class HashBuilder < ResultBuilder
    # Initialize hash builder.
    #
    # @param context [Context] Parse context
    #
    def initialize(context)
      super(context)
      @hash = {}
    end

    # Add key-value pair.
    #
    # @param key [Symbol] Hash key
    # @param value [Object] Hash value
    # @return [self]
    #
    def add_pair(key, value)
      @hash[key] = value
      self
    end

    # Build hash result.
    #
    # @return [Hash] Constructed hash
    #
    def build
      @hash
    end

    # Release resources (hash cleanup).
    #
    # @return [void]
    #
    def release
      @hash = nil
    end
  end
end