# frozen_string_literal: true

# Execution context for tree transformation rules.
# Provides a clean interface for accessing bound variables within transformation blocks.
#
# @example
#   ctx = Parsanol::Context.new(name: 'Alice', value: 42)
#   ctx.instance_eval { name }  # => 'Alice'
#   ctx.instance_eval { @value }  # => 42
#
# Inspired by Parslet (MIT License).
module Parsanol
  class Context
    include Parsanol

    # Creates a new context with the given bindings.
    # Each binding becomes accessible as both a method and an instance variable.
    #
    # @param bindings [Hash] variable name => value pairs
    def initialize(bindings)
      bindings.each_pair do |key, val|
        # Define accessor method on singleton class
        define_singleton_method(key) { val }
        # Also set as instance variable for @-style access
        instance_variable_set("@#{key}", val)
      end
    end

    private

    # Defines a method on the object's singleton class.
    #
    # @param name [Symbol, String] method name
    # @yield block to execute when method is called
    def define_singleton_method(name, &body)
      singleton_class.define_method(name, &body)
    end
  end
end
