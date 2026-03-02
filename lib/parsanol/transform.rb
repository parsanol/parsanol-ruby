# frozen_string_literal: true

require 'parsanol/pattern'

# Tree transformation engine for converting parse trees into abstract syntax trees.
#
# Transforms expression trees through depth-first post-order traversal.
# When a rule pattern matches a node, that node is replaced by the result
# of the rule's transformation block. Unmatched nodes pass through unchanged.
#
# @example Basic transformation class
#   class NumberTransform < Parsanol::Transform
#     rule(int: simple(:value)) { Integer(value) }
#     rule(float: simple(:value)) { Float(value) }
#   end
#
#   transform = NumberTransform.new
#   transform.apply({ int: '42' })  # => 42
#
# @example Inline transformation definition
#   transform = Parsanol::Transform.new do
#     rule(a: simple(:x)) { x.upcase }
#   end
#   transform.apply({ a: 'hello' })  # => 'HELLO'
#
# @example Using context for external dependencies
#   builder = AstBuilder.new
#   transform = Parsanol::Transform.new do
#     rule(expr: simple(:e)) { builder.build_node(e) }
#     rule(expr: simple(:e)) { |ctx| ctx[:builder].build_node(e) }
#   end
#   transform.apply(tree, builder: builder)
#
# Rule blocks can have two forms:
# - Zero-arity: executed in a context where pattern bindings are local variables
# - Arity-1: receives a hash of bindings as the argument
#
# Inspired by tree transformation patterns in parser combinators.
#
module Parsanol
  class Transform
    include Parsanol

    # Class-level rule definition for subclass inheritance.
    class << self
      include Parsanol

      # Defines a transformation rule at the class level.
      # Rules are inherited by subclasses and evaluated in reverse order
      # (most recently defined rules have highest precedence).
      #
      # @param expression [Object] pattern to match against tree nodes
      # @yield block to execute when pattern matches, receives bindings
      # @return [Array] the updated rules list
      #
      def rule(expression, &transformer)
        class_rules.unshift([Parsanol::Pattern.new(expression), transformer])
      end

      # Returns all class-level rules defined for this transform.
      #
      # @return [Array<Array>] array of [pattern, block] pairs
      #
      def class_rules
        @class_rules ||= []
      end

      # Ensures subclasses inherit parent rules.
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@__transform_rules, class_rules.dup)
      end
    end

    # Creates a new transform instance.
    #
    # @param strict [Boolean] if true, raises on unmatched hash nodes
    # @yield optional block for inline rule definition
    #
    def initialize(strict = false, &definition)
      @strict_mode = strict
      @instance_rules = []

      instance_eval(&definition) if definition
    end

    # Defines an instance-level transformation rule.
    # Instance rules are checked before class rules.
    #
    # @param expression [Object] pattern to match
    # @yield transformation block
    #
    def rule(expression, &transformer)
      @instance_rules.unshift([Parsanol::Pattern.new(expression), transformer])
    end

    # Applies transformation to a parse tree.
    #
    # Performs depth-first post-order traversal, transforming nodes
    # from leaves to root. Context values are available in rule blocks.
    #
    # @param tree [Object] parse tree to transform
    # @param context [Hash, nil] optional context bindings
    # @return [Object] transformed tree
    #
    def apply(tree, context = nil)
      # First, recursively transform children (depth-first)
      transformed = transform_children(tree, context)

      # Then, try to match and transform this node
      attempt_transformation(transformed, context)
    end

    # Returns combined class and instance rules.
    # Instance rules take precedence over class rules.
    #
    # @return [Array<Array>] all applicable rules
    #
    def all_rules
      @instance_rules + self.class.class_rules
    end

    # Executes a transformation block with the given bindings.
    # Public API for testing and advanced usage.
    #
    # @param bindings [Hash] pattern bindings
    # @param block [Proc] transformation block
    # @return [Object] block result
    #
    def call_on_match(bindings, block)
      return nil unless block

      if block.arity == 1
        block.call(bindings)
      else
        Context.new(bindings).instance_eval(&block)
      end
    end

    private

    # Recursively transforms child nodes based on tree type.
    #
    # @param node [Object] current tree node
    # @param ctx [Hash, nil] context bindings
    # @return [Object] node with transformed children
    #
    def transform_children(node, ctx)
      case node
      when Hash
        transform_hash_children(node, ctx)
      when Array
        transform_array_children(node, ctx)
      else
        node
      end
    end

    # Transforms all values in a hash.
    #
    def transform_hash_children(hash, ctx)
      result = {}
      hash.each { |key, val| result[key] = apply(val, ctx) }
      result
    end

    # Transforms all elements in an array.
    #
    def transform_array_children(array, ctx)
      array.map { |element| apply(element, ctx) }
    end

    # Attempts to match a node against all rules and transform if matched.
    #
    # @param node [Object] node to potentially transform
    # @param ctx [Hash, nil] context bindings
    # @return [Object] transformed node or original if no match
    #
    def attempt_transformation(node, ctx)
      all_rules.each do |pattern, block|
        bindings = pattern.match(node, ctx)
        next unless bindings

        return execute_block(block, bindings)
      end

      # No rule matched
      handle_unmatched(node)
    end

    # Executes a transformation block with proper binding context.
    #
    # @param block [Proc] transformation block
    # @param bindings [Hash] matched pattern bindings
    # @return [Object] block result
    #
    def execute_block(block, bindings)
      return nil unless block

      if block.arity == 1
        # Block expects bindings as argument
        block.call(bindings)
      else
        # Block executes in context with bindings as local variables
        Context.new(bindings).instance_eval(&block)
      end
    end

    # Handles nodes that didn't match any rule.
    #
    # @param node [Object] unmatched node
    # @return [Object] the node (or raises in strict mode)
    # @raise [NotImplementedError] if strict mode and node is a Hash
    #
    def handle_unmatched(node)
      return node unless @strict_mode
      return node unless node.is_a?(Hash)

      # In strict mode, provide helpful error about what wasn't matched
      signature = node.transform_values(&:class)
      raise NotImplementedError, "Failed to match #{signature.inspect}"
    end
  end
end

require 'parsanol/context'
