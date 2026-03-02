# frozen_string_literal: true

# FIRST Set Analysis for PEG Grammars
#
# FIRST sets help identify which terminals can appear at the beginning of
# a parse. This is essential for:
# 1. Automatic cut operator insertion (AC-FIRST algorithm)
# 2. Grammar analysis and optimization
# 3. Detecting ambiguous choices
#
# Reference: Mizushima et al. (2010) "Packrat Parsers Can Handle Practical
# Grammars in Mostly Constant Space"
#
module Parsanol
  module FirstSet
    # Sentinel value representing the empty string (ε)
    EPSILON = :epsilon

    # Compute the FIRST set for this parslet atom
    # Returns a Set containing:
    # - Terminal atoms (Str, Re) that can match first
    # - EPSILON if the atom can match empty string
    # - nil elements represent unknown/variable terminals (e.g., any)
    #
    # @return [Set] FIRST set containing terminal atoms or EPSILON
    def first_set
      @first_set ||= compute_first_set
    end

    # Clear cached FIRST set (useful after grammar modifications)
    def clear_first_set_cache
      @first_set_cache = nil
    end

    protected

    # Override in subclasses to compute FIRST set
    # Default: conservative approximation (unknown)
    def compute_first_set
      Set.new([nil]) # nil = unknown terminal
    end

    # Class methods for FIRST set analysis
    class << self
      # Check if two FIRST sets are disjoint
      # Two sets are disjoint if they have no common elements
      # EPSILON is ignored when checking disjointness
      #
      # @param set1 [Set] First FIRST set
      # @param set2 [Set] Second FIRST set
      # @return [Boolean] true if sets are disjoint
      def disjoint?(set1, set2)
        # Remove EPSILON and nil from both sets for comparison
        real_set1 = set1.reject { |x| x == EPSILON || x.nil? }
        real_set2 = set2.reject { |x| x == EPSILON || x.nil? }

        # If either set is empty (only EPSILON/nil), consider disjoint
        return true if real_set1.empty? || real_set2.empty?

        # Check if intersection is empty (using to_a for Opal compatibility)
        (real_set1.to_a & real_set2.to_a).empty?
      end

      # Check if all FIRST sets in a collection are mutually disjoint
      # This is critical for AC-FIRST algorithm - we can only insert
      # cuts when all alternatives have non-overlapping FIRST sets
      #
      # @param sets [Array<Set>] Collection of FIRST sets
      # @return [Boolean] true if all pairs are disjoint
      def all_disjoint?(sets)
        # Need at least 2 sets to check disjointness
        return true if sets.length < 2

        # Check all pairs
        sets.combination(2).all? { |s1, s2| disjoint?(s1, s2) }
      end
    end
  end
end
