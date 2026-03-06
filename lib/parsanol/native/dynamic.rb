# frozen_string_literal: true

require 'json'

module Parsanol
  module Native
    # Manages Ruby callbacks for dynamic atoms
    #
    # Dynamic atoms allow runtime-determined parsing by invoking Ruby code
    # during parsing. This module provides:
    # - Registration of Ruby procs as callbacks
    # - Thread-safe callback storage
    # - GC-safe references (callbacks are kept alive while registered)
    #
    # @example Basic usage
    #   # Register a callback
    #   callback_id = Parsanol::Native::Dynamic.register(->(ctx) {
    #     ctx[:mode] == 'A' ? str('alpha') : str('beta')
    #   })
    #
    #   # Use in grammar
    #   grammar = str('MODE:').capture(:mode) >> dynamic(callback_id)
    #
    #   # Unregister when done
    #   Parsanol::Native::Dynamic.unregister(callback_id)
    #
    module Dynamic
      # Callback storage (callback_id => block)
      # This keeps strong references to prevent GC
      @callbacks = {}
      @mutex = Mutex.new
      @next_id = 1_000_000 # Start high to avoid conflicts with Rust-side IDs

      class << self
        # Register a Ruby block as a dynamic callback
        #
        # @param block [Proc] The block to register (must accept a context hash)
        # @param description [String, nil] Optional description for debugging
        # @return [Integer] Unique callback ID for use in grammar
        #
        # @example
        #   id = Parsanol::Native::Dynamic.register(->(ctx) {
        #     case ctx[:type]
        #     when 'int' then str('integer')
        #     when 'str' then str('string')
        #     else nil
        #     end
        #   })
        #
        def register(block, description: nil)
          # Register with Rust FFI
          ffi_id = Native.register_callback(@next_id, description || "Ruby callback ##{@next_id}")

          # Also keep a Ruby-side reference for GC safety
          @mutex.synchronize do
            @callbacks[ffi_id] = {
              block: block,
              description: description || "Ruby callback ##{ffi_id}"
            }
          end

          ffi_id
        end

        # Unregister a callback (free memory)
        #
        # @param callback_id [Integer] The callback ID to remove
        # @return [Boolean] True if the callback was found and removed
        #
        def unregister(callback_id)
          # Remove from Rust FFI
          Native.unregister_callback(callback_id)

          # Remove from Ruby storage
          @mutex.synchronize do
            @callbacks.delete(callback_id)
          end
        end

        # Get the description of a registered callback
        #
        # @param callback_id [Integer] The callback ID
        # @return [String, nil] The description or nil if not found
        #
        def description(callback_id)
          # Try Ruby-side first
          ruby_desc = @mutex.synchronize do
            @callbacks[callback_id]&.dig(:description)
          end

          return ruby_desc if ruby_desc

          # Fall back to FFI
          Native.get_callback_description(callback_id)
        end

        # Get the number of registered callbacks
        #
        # @return [Integer] Number of registered callbacks
        #
        def count
          Native.callback_count
        end

        # Clear all callbacks (for testing)
        #
        # WARNING: This clears all callbacks globally, including those
        # registered by other code. Use with caution.
        #
        def clear
          Native.clear_callbacks
          @mutex.synchronize { @callbacks.clear }
        end

        # Check if a callback is registered
        #
        # @param callback_id [Integer] The callback ID
        # @return [Boolean] True if registered
        #
        def registered?(callback_id)
          @mutex.synchronize { @callbacks.key?(callback_id) } ||
            Native.has_callback(callback_id)
        end

        # Invoke a callback from Rust (called via FFI)
        #
        # @param callback_id [Integer] The callback ID
        # @param context [Hash] The context hash from Rust
        # @return [Object, nil] The returned atom (parslet) or nil
        #
        def invoke_from_rust(callback_id, context)
          block = @mutex.synchronize { @callbacks[callback_id]&.dig(:block) }
          return nil unless block

          # Build DynamicContext from hash
          ctx = DynamicContext.new(
            context[:input],
            context[:pos],
            context[:captures].transform_keys(&:to_sym)
          )

          # Call the block
          result = block.call(ctx)

          return nil unless result

          # Return the result (should be a parslet/atom)
          result
        rescue StandardError => e
          warn "[Parsanol::Native::Dynamic] Invoke error: #{e.message}"
          nil
        end
      end
    end

    # Context object passed to dynamic callbacks
    #
    # Provides read-only access to the parsing context including
    # input string, current position, and captured values.
    #
    # @example
    #   dynamic { |ctx|
    #     if ctx[:mode] == 'strict'
    #       str('strict_value')
    #     else
    #       str('relaxed_value')
    #     end
    #   }
    #
    class DynamicContext
      # @return [String] The full input string being parsed
      attr_reader :input

      # @return [Integer] Current byte position in the input
      attr_reader :pos

      # @return [Hash<Symbol, String>] Captured values
      attr_reader :captures

      def initialize(input, pos, captures)
        @input = input
        @pos = pos
        @captures = captures.transform_keys(&:to_sym)
      end

      # Get a captured value by name
      #
      # @param name [Symbol, String] The capture name
      # @return [String, nil] The captured value or nil
      #
      def [](name)
        @captures[name.to_sym]
      end

      # Check if a capture exists
      #
      # @param name [Symbol, String] The capture name
      # @return [Boolean] True if the capture exists
      #
      def key?(name)
        @captures.key?(name.to_sym)
      end
      alias has_key? key?

      # Get the remaining input from the current position
      #
      # @return [String] The remaining input
      #
      def remaining
        @input[@pos..] || ''
      end

      # Check if at end of input
      #
      # @return [Boolean] True if at end
      #
      def eos?
        @pos >= @input.length
      end
      alias at_end? eos?

      # Get a slice of the input
      #
      # @param start [Integer] Start position (relative to current pos if negative)
      # @param length [Integer, nil] Length of slice (nil = to end)
      # @return [String] The sliced input
      #
      def slice(start, length = nil)
        if length
          @input[@pos + start, length]
        else
          @input[@pos + start..]
        end
      end
    end
  end
end
