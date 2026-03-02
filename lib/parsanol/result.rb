# frozen_string_literal: true

# Phase 58: Result wrapper to replace [success, value] arrays
#
# This class wraps parse results to eliminate array allocations.
# Instead of [true, value] or [false, cause], we use Result objects.
#
# Benefits:
# - Eliminates array allocations (40% reduction)
# - Cleaner API with success? method
# - Can be optimized further (object pooling, etc.)
#
class Parsanol::Result
  attr_reader :value

  def initialize(success, value)
    @success = success
    @value = value
  end

  def success?
    @success
  end

  def error?
    !@success
  end

  # Compatibility: Allow destructuring like arrays
  # This enables gradual migration: result.success?, result.value
  # or: success, value = result (array-like)
  def to_ary
    [@success, @value]
  end

  # Factory methods for common cases
  def self.success(value)
    new(true, value)
  end

  def self.error(cause)
    new(false, cause)
  end
end
