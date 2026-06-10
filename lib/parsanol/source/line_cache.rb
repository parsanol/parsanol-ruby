# frozen_string_literal: true

# Line position caching for efficient line/column lookups.
# Stores line ending positions to enable O(log n) line number queries.
#
# Inspired by Parslet (MIT License).

module Parsanol
  class Source
    # Caches line ending positions for quick line/column resolution.
    # Uses binary search for efficient position lookup.
    class LineCache
      def initialize(buffer = nil, start_offset = 0)
        # Array of byte offsets where each line ends
        @breaks = []
        @breaks.extend(IntervalLookup)
        @max_scanned = nil
        @buffer = buffer
        @start_offset = start_offset
        @fully_scanned = false
      end

      # Converts a byte offset to [line_number, column_number].
      # Line and column numbers are 1-indexed.
      #
      # @param position [Integer, #bytepos] the byte offset to convert
      # @return [Array<Integer, Integer>] [line, column] tuple
      def line_and_column(position)
        scan_buffer_once

        position = position.bytepos if position.respond_to?(:bytepos)

        line_idx = @breaks.lower_bound_index(position)

        if line_idx
          # Found a line ending after this position
          line_start = line_idx.positive? ? @breaks[line_idx - 1] : 0
          [line_idx + 1, position - line_start + 1]
        else
          # Position is beyond all known line endings
          line_start = @breaks.last || 0
          [@breaks.size + 1, position - line_start + 1]
        end
      end

      # Scans a string buffer for line endings and caches their positions.
      # Avoids re-scanning already processed regions. Incremental callers must
      # feed windows of one consistent input in monotonically advancing,
      # contiguous-or-overlapping order; non-contiguous or out-of-order scans
      # are skipped where already covered and can miss line endings in gaps.
      #
      # @param start_offset [Integer] the byte offset where buffer starts
      # @param buffer [String] the string content to scan
      def scan_for_line_endings(start_offset, buffer)
        return unless buffer

        scanner = StringScanner.new(buffer)
        if scanner.exist?(/\n/)
          # Skip already-scanned content. @max_scanned can extend past this
          # buffer's window (it advances to the end of every scanned buffer),
          # so clamp to the window to keep the scanner position valid.
          if @max_scanned && start_offset < @max_scanned
            scanner.pos = [@max_scanned - start_offset, buffer.bytesize].min
          end

          # Record all newline positions
          while scanner.skip_until(/\n/)
            @max_scanned = start_offset + scanner.pos
            @breaks << @max_scanned
          end
        end

        @max_scanned = [@max_scanned || start_offset, start_offset + buffer.bytesize].max
        return unless buffer.equal?(@buffer) && start_offset == @start_offset

        @fully_scanned = true
        # The one-shot buffer is no longer needed; drop the reference so
        # retained Slices do not pin the entire input string.
        @buffer = nil
      end

      private

      def scan_buffer_once
        return if @fully_scanned || !@buffer

        scan_for_line_endings(@start_offset, @buffer)
      end
    end

    # Mixin providing binary search for interval containment queries.
    # Treats array values as interval endpoints where each interval [n-1, n]
    # is represented by value at index n.
    #
    # @example
    #   [10, 20, 30] represents intervals [0,10], (10,20], (20,30]
    module IntervalLookup
      # Calculates midpoint index for binary search.
      # Uses floor to ensure integer result.
      def midpoint_index(lo, hi)
        lo + ((hi - lo) / 2).floor
      end

      # Finds the index of the first value greater than the bound.
      # Returns nil if no such value exists.
      #
      # @param bound [Numeric] the value to search against
      # @return [Integer, nil] index of first value > bound, or nil
      def lower_bound_index(bound)
        return nil if empty?
        return nil unless last > bound

        lo = 0
        hi = size - 1

        loop do
          mid = midpoint_index(lo, hi)

          if self[mid] > bound
            hi = mid
          else
            lo = mid + 1
          end

          return hi if hi <= lo
        end
      end
    end
  end
end
