# Automatic Cut Insertion (AC-FIRST Algorithm)
#
# This optimizer implements the AC-FIRST algorithm from Mizushima et al. (2010)
# to automatically insert cut operators when alternatives have disjoint FIRST sets.
#
# When all alternatives in a choice have non-overlapping FIRST sets, we can safely
# insert a cut after the deterministic prefix, since backtracking will never be
# needed.
#
# Example:
#   str('if') >> condition >> then_clause |
#   str('while') >> condition >> body |
#   str('print') >> expression
#
# Becomes:
#   str('if').cut >> condition >> then_clause |
#   str('while').cut >> condition >> body |
#   str('print').cut >> expression
#
# Reference: Mizushima et al. (2010) "Packrat Parsers Can Handle Practical
# Grammars in Mostly Constant Space"
#
class Parsanol::Optimizers::CutInserter
  # Optimize a parslet by inserting cuts where safe
  # Recursively traverses the grammar AST
  #
  # @param parslet [Parsanol::Atoms::Base] The parslet to optimize
  # @return [Parsanol::Atoms::Base] Optimized parslet with cuts inserted
  def optimize(parslet)
    case parslet
    when Parsanol::Atoms::Alternative
      optimize_alternative(parslet)
    when Parsanol::Atoms::Sequence
      optimize_sequence(parslet)
    when Parsanol::Atoms::Repetition
      optimize_repetition(parslet)
    when Parsanol::Atoms::Named
      optimize_named(parslet)
    else
      # Return atom unchanged (Str, Re, Lookahead, etc.)
      parslet
    end
  end

  private

  # Optimize an Alternative atom by inserting cuts when all alternatives
  # have disjoint FIRST sets
  def optimize_alternative(alt)
    alternatives = alt.alternatives
    first_sets = alternatives.map(&:first_set)

    # Only optimize if all FIRST sets are disjoint
    unless Parsanol::FirstSet.all_disjoint?(first_sets)
      # Not safe to insert cuts - return alternatives with recursive optimization
      optimized = alternatives.map { |a| optimize(a) }
      return Parsanol::Atoms::Alternative.new(*optimized)
    end

    # All FIRST sets are disjoint - safe to insert cuts!
    # Insert cuts after deterministic prefixes
    optimized = alternatives.map do |alternative|
      insert_cut_if_safe(alternative)
    end

    Parsanol::Atoms::Alternative.new(*optimized)
  end

  # Optimize a Sequence atom by recursively optimizing its elements
  def optimize_sequence(seq)
    optimized_parslets = seq.parslets.map { |p| optimize(p) }
    Parsanol::Atoms::Sequence.new(*optimized_parslets)
  end

  # Optimize a Repetition atom by recursively optimizing its parslet
  def optimize_repetition(rep)
    optimized_parslet = optimize(rep.parslet)
    # Create new repetition with same min/max
    # Note: We use default tag since it's not exposed as a reader
    Parsanol::Atoms::Repetition.new(
      optimized_parslet,
      rep.min,
      rep.max
    )
  end

  # Optimize a Named atom by recursively optimizing its parslet
  def optimize_named(named)
    optimized_parslet = optimize(named.parslet)
    optimized_parslet.as(named.name)
  end

  # Insert a cut after the deterministic prefix if safe
  # For sequences: find longest prefix without EPSILON
  # For other atoms: cut the whole thing if it doesn't include EPSILON
  def insert_cut_if_safe(parslet)
    # For sequences, find the longest safe prefix
    if parslet.is_a?(Parsanol::Atoms::Sequence)
      prefix_parslets = find_deterministic_prefix(parslet)
      if prefix_parslets && !prefix_parslets.empty?
        return build_cut_sequence(parslet, prefix_parslets)
      end
    end

    # For other atoms, cut the whole thing if safe
    if safe_to_cut?(parslet)
      return parslet.cut
    end

    # Not safe to cut - recursively optimize and return
    optimize(parslet)
  end

  # Find the longest deterministic prefix of a sequence
  # A deterministic prefix doesn't include EPSILON in its FIRST set
  #
  # @param sequence [Parsanol::Atoms::Sequence] The sequence to analyze
  # @return [Array<Parsanol::Atoms::Base>] Prefix parslets, or nil if none
  def find_deterministic_prefix(sequence)
    parslets = sequence.parslets
    prefix_length = 0

    # Find longest prefix where no element can match empty
    parslets.each do |p|
      break if p.first_set.include?(Parsanol::FirstSet::EPSILON)
      prefix_length += 1
    end

    prefix_length > 0 ? parslets[0...prefix_length] : nil
  end

  # Check if it's safe to cut after this parslet
  # Safe if the parslet doesn't have EPSILON in its FIRST set
  # (i.e., it always consumes input)
  def safe_to_cut?(parslet)
    first = parslet.first_set
    # Don't cut if EPSILON is in FIRST set (might not consume)
    # Also don't cut if FIRST set contains only nil (unknown)
    return false if first.include?(Parsanol::FirstSet::EPSILON)
    return false if first.all?(&:nil?)
    true
  end

  # Build a new sequence with a cut after the prefix
  #
  # @param sequence [Parsanol::Atoms::Sequence] Original sequence
  # @param prefix_parslets [Array] Parslets forming the deterministic prefix
  # @return [Parsanol::Atoms::Base] New sequence with cut inserted
  def build_cut_sequence(sequence, prefix_parslets)
    # Recursively optimize prefix parslets
    optimized_prefix = prefix_parslets.map { |p| optimize(p) }

    # Build prefix (single parslet or sequence)
    prefix = if optimized_prefix.length == 1
      optimized_prefix.first
    else
      Parsanol::Atoms::Sequence.new(*optimized_prefix)
    end

    # Get remaining parslets after prefix
    remaining = sequence.parslets[prefix_parslets.length..-1]

    # Recursively optimize remaining parslets
    optimized_remaining = remaining.map { |p| optimize(p) }

    # Build final sequence with cut
    if optimized_remaining.empty?
      # Prefix is the entire sequence
      prefix.cut
    else
      # Prefix + cut + remaining
      Parsanol::Atoms::Sequence.new(prefix.cut, *optimized_remaining)
    end
  end
end
