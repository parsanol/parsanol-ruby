# frozen_string_literal: true

# Pattern matching for parse tree structures.
#
# This class provides tree pattern matching functionality where patterns
# are expressed using hashes for key-value structures and arrays for
# sequences. Leaf nodes can be matched using binding expressions.
#
# @example Matching a function call tree
#   tree = {
#     function_call: {
#       name: 'foobar',
#       args: [1, 2, 3]
#     }
#   }
#
#   pattern = Parsanol::Pattern.new(
#     function_call: { name: simple(:name), args: sequence(:args) }
#   )
#   bindings = pattern.match(tree)
#   # => { name: 'foobar', args: [1, 2, 3] }
#
# Note: Pattern matching is performed at a single subtree level only.
# For recursive matching throughout a tree, use Parsanol::Transform.
#
# Inspired by pattern matching concepts in functional programming.
#
class Parsanol::Pattern
  # Creates a new pattern matcher with the given pattern structure.
  #
  # @param pattern [Hash, Array, Object] the pattern to match against
  def initialize(pattern)
    @pattern_def = pattern
  end

  # Attempts to match the given subtree against this pattern.
  #
  # Returns a hash of variable bindings if matching succeeds, or nil if
  # the pattern does not match. Existing bindings can be provided to
  # verify consistency with previous matches.
  #
  # @param subtree [Object] the tree or value to match
  # @param bindings [Hash, nil] existing variable bindings to verify
  # @return [Hash, nil] bindings hash on success, nil on failure
  #
  # @example Matching with existing bindings
  #   pattern = Parsanol::Pattern.new('a')
  #   pattern.match('a', { foo: 'bar' })
  #   # => { foo: 'bar' }
  #
  def match(subtree, bindings = nil)
    current_bindings = bindings ? bindings.dup : {}
    check_match(subtree, @pattern_def, current_bindings) ? current_bindings : nil
  end

  private

  # Core matching dispatcher based on types.
  # Routes to appropriate matching strategy based on tree and pattern types.
  #
  # @param target [Object] the value being matched
  # @param pattern_val [Object] the pattern to match against
  # @param captured [Hash] accumulated bindings (modified in place)
  # @return [Boolean] true if match succeeds
  #
  def check_match(target, pattern_val, captured)
    case
    when target.is_a?(Hash) && pattern_val.is_a?(Hash)
      match_hash_structure(target, pattern_val, captured)
    when target.is_a?(Array) && pattern_val.is_a?(Array)
      match_array_elements(target, pattern_val, captured)
    else
      match_leaf_value(target, pattern_val, captured)
    end
  end

  # Matches leaf values (non-containers).
  # Handles direct equality, case equality, and binding capture.
  #
  # @param target [Object] the value being matched
  # @param pattern_val [Object] the pattern element
  # @param captured [Hash] bindings hash
  # @return [Boolean] true if match succeeds
  #
  def match_leaf_value(target, pattern_val, captured)
    # Case equality covers exact matches and class matches
    return true if pattern_val === target

    # Check if pattern is a binding expression (like simple(:x))
    if pattern_val.respond_to?(:can_bind?) && pattern_val.can_bind?(target)
      return capture_binding(target, pattern_val, captured)
    end

    # No match possible
    false
  end

  # Handles binding capture for expressions like simple(:name).
  # If the variable is already bound, verifies consistency.
  # Otherwise, creates a new binding.
  #
  # @param value [Object] the value to bind
  # @param binder [Object] the binding expression object
  # @param captured [Hash] bindings hash (modified in place)
  # @return [Boolean] true if binding succeeds
  #
  def capture_binding(value, binder, captured)
    var_key = binder.variable_name

    # Verify existing binding consistency if present
    if var_key && captured.key?(var_key)
      return captured[var_key] == value
    end

    # Store new binding
    captured[var_key] = value if var_key
    true
  end

  # Matches array structures element-by-element.
  # Arrays must have identical length and each element must match.
  #
  # @param target_ary [Array] the array being matched
  # @param pattern_ary [Array] the pattern array
  # @param captured [Hash] bindings hash
  # @return [Boolean] true if all elements match
  #
  def match_array_elements(target_ary, pattern_ary, captured)
    # Length mismatch means no match
    return false unless target_ary.length == pattern_ary.length

    # Each position must match
    target_ary.zip(pattern_ary).all? do |elem, pat|
      check_match(elem, pat, captured)
    end
  end

  # Matches hash structures key-by-key.
  # All keys in pattern must exist in target with matching values.
  #
  # @param target_hash [Hash] the hash being matched
  # @param pattern_hash [Hash] the pattern hash
  # @param captured [Hash] bindings hash
  # @return [Boolean] true if all key-value pairs match
  #
  def match_hash_structure(target_hash, pattern_hash, captured)
    # Size mismatch means no match
    return false unless target_hash.size == pattern_hash.size

    # Verify each expected key exists with matching value
    pattern_hash.each do |key, expected|
      return false unless target_hash.key?(key)

      actual = target_hash[key]
      return false unless check_match(actual, expected, captured)
    end

    true
  end
end
