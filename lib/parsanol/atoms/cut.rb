# Cut operator for PEG grammars
#
# A cut operator (↑) instructs the parser to discard backtrack information
# at a specific point. This enables more aggressive cache eviction and can
# reduce space complexity from O(n) to O(1).
#
# Reference: Mizushima et al. (2010) "Packrat Parsers Can Handle Practical
# Grammars in Mostly Constant Space"
#
# Example:
#
#   rule(:statement) {
#     str('if').cut >> condition >> then_clause |
#     str('while').cut >> condition >> body |
#     str('print').cut >> expression
#   }
#
# After 'if' succeeds, the cut discards backtrack info for 'while' and 'print'.
# This means if the parse fails later in the 'if' branch, we won't try the
# other alternatives.
#
class Parsanol::Atoms::Cut < Parsanol::Atoms::Base
  attr_reader :parslet

  def initialize(parslet)
    super()
    @parslet = parslet
  end

  def try(source, context, consume_all)
    # First, try to match the parslet
    success, value = parslet.apply(source, context, consume_all)

    return [success, value] unless success

    # On success, signal to context that a cut has occurred
    # This allows the context to:
    # 1. Mark the current position as a cut point
    # 2. Empty the backtrack stack (we won't backtrack past here)
    # 3. Aggressively evict cache entries before this position
    if context.respond_to?(:cut!)
      context.cut!(source.bytepos)
    end

    return [success, value]
  end

  # Cut doesn't need caching - it's a thin wrapper
  def cached?
    false
  end

  def to_s_inner(prec)
    "#{parslet.to_s(prec)}↑"
  end

  # FIRST set of cut is same as wrapped parslet
  # Cut doesn't change matching behavior, only affects backtracking
  def compute_first_set
    parslet.first_set
  end
end
