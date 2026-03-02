# frozen_string_literal: true

module Parsanol
  # Module for streaming builder callbacks.
  # Include this module in your builder class to receive callbacks
  # during single-pass parsing with the streaming builder API.
  #
  # The streaming builder API allows maximum performance by eliminating
  # intermediate AST construction. Instead, callbacks are invoked as
  # parsing progresses, allowing you to construct custom output directly.
  #
  # @example Basic string collector
  #   class StringCollector
  #     include Parsanol::BuilderCallbacks
  #
  #     def initialize
  #       @strings = []
  #     end
  #
  #     def on_string(value, offset, length)
  #       @strings << value
  #     end
  #
  #     def finish
  #       @strings
  #     end
  #   end
  #
  #   grammar = Parsanol::Native.serialize_grammar(parser.root)
  #   builder = StringCollector.new
  #   result = Parsanol::Native.parse_with_builder(grammar, input, builder)
  #   # result: ["hello", "world"]
  #
  # @example Building a typed AST
  #   class AstBuilder
  #     include Parsanol::BuilderCallbacks
  #
  #     def initialize
  #       @stack = []
  #       @current_hash = nil
  #       @current_key = nil
  #     end
  #
  #     def on_hash_start(size = nil)
  #       @stack.push(@current_hash) if @current_hash
  #       @current_hash = {}
  #     end
  #
  #     def on_hash_end(size)
  #       finished = @current_hash
  #       @current_hash = @stack.pop
  #       if @current_hash && @current_key
  #         @current_hash[@current_key] = finished
  #         @current_key = nil
  #       end
  #       finished
  #     end
  #
  #     def on_hash_key(key)
  #       @current_key = key
  #     end
  #
  #     def on_string(value, offset, length)
  #       if @current_hash && @current_key
  #         @current_hash[@current_key] = value
  #         @current_key = nil
  #       end
  #     end
  #
  #     def finish
  #       @current_hash
  #     end
  #   end
  #
  module BuilderCallbacks
    # Called when parsing starts.
    #
    # @param input [String] The input being parsed
    # @return [void]
    def on_start(input); end

    # Called when parsing succeeds.
    #
    # @return [void]
    def on_success; end

    # Called when parsing fails.
    #
    # @param message [String] The error message
    # @return [void]
    def on_error(message); end

    # Called when a string value is matched.
    #
    # @param value [String] The matched string value
    # @param offset [Integer] Byte offset in the original input
    # @param length [Integer] Length of the matched string in bytes
    # @return [void]
    def on_string(value, offset, length); end

    # Called when an integer value is matched.
    #
    # @param value [Integer] The matched integer value
    # @return [void]
    def on_int(value); end

    # Called when a float value is matched.
    #
    # @param value [Float] The matched float value
    # @return [void]
    def on_float(value); end

    # Called when a boolean value is matched.
    #
    # @param value [Boolean] The matched boolean value
    # @return [void]
    def on_bool(value); end

    # Called when a nil/null value is matched.
    #
    # @return [void]
    def on_nil; end

    # Called when starting to parse a hash/object.
    # Use this to initialize state for collecting key-value pairs.
    #
    # @param size [Integer, nil] Expected number of entries (may be nil)
    # @return [void]
    def on_hash_start(size = nil); end

    # Called when finishing parsing a hash/object.
    #
    # @param size [Integer] Actual number of entries
    # @return [void]
    def on_hash_end(size); end

    # Called when a hash key is encountered.
    # The next value callback(s) will provide the value for this key.
    #
    # @param key [String] The hash key name
    # @return [void]
    def on_hash_key(key); end

    # Called when a hash value is about to be parsed.
    # Called after on_hash_key for the corresponding value.
    #
    # @param key [String] The hash key name
    # @return [void]
    def on_hash_value(key); end

    # Called when starting to parse an array.
    # Use this to initialize state for collecting array elements.
    #
    # @param size [Integer, nil] Expected number of elements (may be nil)
    # @return [void]
    def on_array_start(size = nil); end

    # Called when an array element is about to be parsed.
    #
    # @param index [Integer] The index of the element
    # @return [void]
    def on_array_element(index); end

    # Called when finishing parsing an array.
    #
    # @param size [Integer] Actual number of elements
    # @return [void]
    def on_array_end(size); end

    # Called when starting to parse a named rule.
    #
    # @param name [String] The rule name
    # @return [void]
    def on_named_start(name); end

    # Called when finishing parsing a named rule.
    #
    # @param name [String] The rule name
    # @return [void]
    def on_named_end(name); end

    # Called when parsing is complete.
    # Override this method to return your final constructed result.
    #
    # @return [Object] The final result of the builder
    def finish; end
  end

  # Built-in builders for common use cases
  module Builders
    # Debug builder that collects all events as strings.
    # Useful for understanding the parsing flow.
    class DebugBuilder
      include BuilderCallbacks

      attr_reader :events

      def initialize
        @events = []
      end

      def on_start(input)
        @events << "start: #{input.inspect}"
      end

      def on_success
        @events << "success"
      end

      def on_error(message)
        @events << "error: #{message}"
      end

      def on_string(value, offset, length)
        @events << "string: #{value.inspect} @ #{offset}(#{length})"
      end

      def on_int(value)
        @events << "int: #{value}"
      end

      def on_float(value)
        @events << "float: #{value}"
      end

      def on_bool(value)
        @events << "bool: #{value}"
      end

      def on_nil
        @events << "nil"
      end

      def on_hash_start(size = nil)
        @events << "hash_start(#{size.inspect})"
      end

      def on_hash_end(size)
        @events << "hash_end(#{size})"
      end

      def on_hash_key(key)
        @events << "hash_key: #{key.inspect}"
      end

      def on_hash_value(key)
        @events << "hash_value: #{key.inspect}"
      end

      def on_array_start(size = nil)
        @events << "array_start(#{size.inspect})"
      end

      def on_array_element(index)
        @events << "array_element[#{index}]"
      end

      def on_array_end(size)
        @events << "array_end(#{size})"
      end

      def on_named_start(name)
        @events << "named_start: #{name}"
      end

      def on_named_end(name)
        @events << "named_end: #{name}"
      end

      def finish
        @events.join("\n")
      end
    end

    # Builder that collects all string values.
    class StringCollector
      include BuilderCallbacks

      attr_reader :strings

      def initialize
        @strings = []
      end

      def on_start(input); end

      def on_success; end

      def on_error(message); end

      def on_string(value, offset, length)
        @strings << value
      end

      def finish
        @strings
      end
    end

    # Builder that counts nodes by type.
    class NodeCounter
      include BuilderCallbacks

      attr_reader :counts

      def initialize
        @counts = Hash.new(0)
      end

      def on_start(input); end

      def on_success; end

      def on_error(message); end

      def on_string(value, offset, length)
        @counts[:string] += 1
      end

      def on_int(value)
        @counts[:int] += 1
      end

      def on_float(value)
        @counts[:float] += 1
      end

      def on_bool(value)
        @counts[:bool] += 1
      end

      def on_nil
        @counts[:nil] += 1
      end

      def on_hash_start(size = nil)
        @counts[:hash] += 1
      end

      def on_array_start(size = nil)
        @counts[:array] += 1
      end

      def on_named_start(name)
        @counts[:named] += 1
      end

      def finish
        @counts
      end
    end
  end
end
