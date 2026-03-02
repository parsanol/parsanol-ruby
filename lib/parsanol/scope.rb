# frozen_string_literal: true

# Scoped variable bindings for parser context management. Provides a
# stack-like interface for creating nested scopes that inherit from
# parent scopes.
#
# @example Basic usage
#   scope = Parsanol::Scope.new
#   scope[:x] = 1
#   scope.push      # Create nested scope
#   scope[:x]       # => 1 (inherited from parent)
#   scope[:y] = 2
#   scope.pop       # Return to parent scope
#   scope[:y]       # raises NotFound
#
# Inspired by lexical scoping patterns in programming languages.
#
module Parsanol
  class Scope
    # Error raised when attempting to access an undefined binding.
    class UndefinedVariable < StandardError
    end
    # Legacy alias for backward compatibility
    NotFound = UndefinedVariable

    # Internal class representing a single scope level. Each frame can
    # look up values in its parent frame if not found locally.
    class Frame
      # @return [Frame, nil] parent frame in the scope chain
      attr_reader :parent_frame

      # Creates a new frame optionally linked to a parent.
      #
      # @param parent [Frame, nil] the parent frame to inherit from
      def initialize(parent = nil)
        @parent_frame = parent
        @bindings = {}
      end

      # Retrieves a value by key, searching parent frames if necessary.
      #
      # @param key [Symbol] the variable name to look up
      # @return [Object] the bound value
      # @raise [UndefinedVariable] if key not found in any frame
      def fetch(key)
        if @bindings.key?(key)
          @bindings[key]
        elsif @parent_frame
          @parent_frame.fetch(key)
        else
          raise UndefinedVariable, "No binding for #{key.inspect}"
        end
      end

      # Stores a value in the current frame.
      #
      # @param key [Symbol] the variable name
      # @param value [Object] the value to bind
      # @return [Object] the stored value
      def store(key, value)
        @bindings[key] = value
      end

      alias [] fetch
      alias []= store
    end

    # Creates a new scope with an empty root frame.
    def initialize
      @active_frame = Frame.new
    end

    # Retrieves a value from the current scope chain.
    #
    # @param key [Symbol] the variable name
    # @return [Object] the bound value
    # @raise [UndefinedVariable] if not found
    def [](key)
      @active_frame.fetch(key)
    end

    # Stores a value in the current frame.
    #
    # @param key [Symbol] the variable name
    # @param value [Object] the value to bind
    def []=(key, value)
      @active_frame.store(key, value)
    end

    # Creates a new nested scope frame. Call #pop to restore.
    #
    # @return [void]
    def push
      @active_frame = Frame.new(@active_frame)
    end

    # Returns to the parent scope frame.
    #
    # @return [void]
    def pop
      @active_frame = @active_frame.parent_frame
    end
  end
end
