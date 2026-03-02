# frozen_string_literal: true

# Pattern binding classes for transform pattern matching.
# These classes represent placeholders in transform patterns that capture
# values during pattern matching.
#
# Inspired by Parslet (MIT License).

# Base class for all pattern bindings. Matches any subtree regardless of type.
# Used internally by Parsanol::Transform for pattern-based tree transformation.
class Parsanol::Pattern::SubtreeBind < Struct.new(:symbol)
  # Returns the symbol that will be bound during matching.
  #
  # @return [Symbol] the binding variable name
  def variable_name
    symbol
  end

  # Human-readable representation of this binding.
  #
  # @return [String] description of the binding
  def inspect
    "#{binding_category}(#{symbol.inspect})"
  end

  # Determines if this binding can match the given subtree.
  # SubtreeBind is the most permissive - matches anything.
  #
  # @param subtree [Object] the value to test
  # @return [true] always returns true
  def can_bind?(subtree)
    true
  end

  private

  # Extracts the binding category name from the class name.
  #
  # @return [String] lowercase category name
  def binding_category
    class_match = self.class.name.match(/::(\w+)Bind\z/)
    return class_match[1].downcase if class_match

    # Fallback for unexpected class names
    'subtree'
  end
end

# Binding that matches only simple (leaf) values.
# Simple values are those that are neither Hash nor Array.
#
# @example
#   simple(:x)  # matches strings, numbers, slices - but not hashes or arrays
class Parsanol::Pattern::SimpleBind < Parsanol::Pattern::SubtreeBind
  # Tests if the subtree is a simple leaf value.
  #
  # @param subtree [Object] the value to test
  # @return [Boolean] true if subtree is not a Hash or Array
  def can_bind?(subtree)
    !subtree.is_a?(Hash) && !subtree.is_a?(Array)
  end
end

# Binding that matches sequences of simple leaf values.
# A sequence is an Array where no element is a Hash or Array.
#
# @example
#   sequence(:items)  # matches ['a', 'b', 'c'] but not ['a', {x: 1}]
class Parsanol::Pattern::SequenceBind < Parsanol::Pattern::SubtreeBind
  # Tests if the subtree is a flat sequence of simple values.
  #
  # @param subtree [Object] the value to test
  # @return [Boolean] true if subtree is an Array of simple values
  def can_bind?(subtree)
    return false unless subtree.is_a?(Array)

    subtree.none? { |element| element.is_a?(Hash) || element.is_a?(Array) }
  end
end
