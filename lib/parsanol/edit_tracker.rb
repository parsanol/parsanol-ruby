# Edit tracking for GPeg-style incremental parsing
# Based on the GPeg paper: "Fast Incremental PEG Parsing" (Yedidia, SLE 2021)
#
# Tracks edits to the input as [position, delta] pairs and enables lazy shifting
# of cached intervals without rebuilding the entire cache (O(1) edit cost).
#
class Parsanol::EditTracker
  # An edit operation: insertion (+delta) or deletion (-delta) at a position
  class Edit
    attr_reader :position, :delta

    def initialize(position, delta)
      @position = position
      @delta = delta
    end

    def to_s
      if @delta > 0
        "Insert(#{@delta} chars at #{@position})"
      else
        "Delete(#{-@delta} chars at #{@position})"
      end
    end
  end

  def initialize
    @edits = []  # List of edits in chronological order
  end

  # Record an insertion at position
  # @param position [Integer] Where the insertion occurred
  # @param length [Integer] Number of characters inserted
  def insert(position, length)
    @edits << Edit.new(position, length)
  end

  # Record a deletion at position
  # @param position [Integer] Where the deletion occurred
  # @param length [Integer] Number of characters deleted
  def delete(position, length)
    @edits << Edit.new(position, -length)
  end

  # Shift an interval based on accumulated edits
  # Returns the shifted interval [low', high') or nil if interval is invalidated
  #
  # An interval is invalidated if any edit overlaps with it, as the cached
  # parse result is no longer valid.
  #
  # @param low [Integer] Interval start position
  # @param high [Integer] Interval end position (exclusive)
  # @return [Array<Integer>, nil] Shifted [low, high) or nil if invalidated
  def shift_interval(low, high)
    shifted_low = low
    shifted_high = high

    @edits.each do |edit|
      # Skip zero-length edits (no-ops)
      next if edit.delta == 0

      # Check if edit overlaps with current interval
      # Edit overlaps if it occurs within [shifted_low, shifted_high)
      if edit.position >= shifted_low && edit.position < shifted_high
        # Edit inside interval - invalidate
        return nil
      elsif edit.position < shifted_low
        # Edit before interval - shift both boundaries
        shifted_low += edit.delta
        shifted_high += edit.delta
      elsif edit.position >= shifted_high
        # Edit after interval - no shift needed
        # Continue to next edit
      end

      # Sanity check: ensure interval remains valid
      return nil if shifted_low < 0 || shifted_high < shifted_low
    end

    [shifted_low, shifted_high]
  end

  # Check if interval needs invalidation (overlaps with any edit)
  # @param low [Integer] Interval start position
  # @param high [Integer] Interval end position (exclusive)
  # @return [Boolean] true if interval should be invalidated
  def invalidates?(low, high)
    shift_interval(low, high).nil?
  end

  # Clear all recorded edits
  def clear
    @edits.clear
  end

  # Number of edits tracked
  def size
    @edits.size
  end

  # Check if any edits have been recorded
  def empty?
    @edits.empty?
  end

  # Get all edits (for debugging)
  attr_reader :edits
end
