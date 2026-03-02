# frozen_string_literal: true

# Fast mode patch for Parslet - matches vanilla parslet 2.0 behavior.
#
# For grammars with many small allocations (like EXPRESS), this is faster
# because the overhead of pool management exceeds the benefit.
#
# Usage:
#   require 'parslet'
#   require 'parsanol/fast_mode'
#   # Now all parsing uses fast mode methods
#

module Parsanol
  FAST_MODE = true

  module Atoms
    # Fast mode Context - matches vanilla parslet 2.0 simplicity
    class Context
      # Override try_with_cache with vanilla-like version (no eviction, no pooling)
      def try_with_cache(obj, source, consume_all)
        beg = source.bytepos

        # Not in cache yet? Return early.
        unless (entry = @cache[beg]&.[](obj.object_id))
          result = obj.try(source, self, consume_all)

          if obj.cached?
            (@cache[beg] ||= {})[obj.object_id] = [result, source.bytepos - beg]
          end

          return result
        end

        # Cache hit
        result, advance = entry
        source.bytepos = beg + advance
        result
      end
    end

    # Fast mode Sequence - direct array creation, no lazy evaluation
    class Sequence
      def try(source, context, consume_all)
        parslets = @parslets

        case parslets.size
        when 1
          success, value = parslets[0].apply(source, context, consume_all)
          return success ? succ([:sequence, value]) : context.err(self, source, @error_msg, [value])
        when 2
          success, v1 = parslets[0].apply(source, context, false)
          return context.err(self, source, @error_msg, [v1]) unless success
          success, v2 = parslets[1].apply(source, context, consume_all)
          return success ? succ([:sequence, v1, v2]) : context.err(self, source, @error_msg, [v2])
        when 3
          success, v1 = parslets[0].apply(source, context, false)
          return context.err(self, source, @error_msg, [v1]) unless success
          success, v2 = parslets[1].apply(source, context, false)
          return context.err(self, source, @error_msg, [v2]) unless success
          success, v3 = parslets[2].apply(source, context, consume_all)
          return success ? succ([:sequence, v1, v2, v3]) : context.err(self, source, @error_msg, [v3])
        else
          result = [:sequence]
          last_idx = parslets.size - 1
          i = 0
          while i <= last_idx
            success, value = parslets[i].apply(source, context, consume_all && i == last_idx)
            return context.err(self, source, @error_msg, [value]) unless success
            result << value
            i += 1
          end
          succ(result)
        end
      end
    end

    # Fast mode Repetition - direct array creation, no lazy evaluation
    class Repetition
      EMPTY_REPETITION_ARRAY = [:repetition].freeze

      def try(source, context, consume_all)
        parslet = @parslet
        min = @min
        max = @max
        tag = @tag

        # Fast path for .maybe
        if min == 0 && max == 1
          success, value = parslet.apply(source, context, false)
          return succ([tag, value]) if success
          return succ(tag == :repetition ? EMPTY_REPETITION_ARRAY : [tag])
        end

        # Fast path for exact count
        if min == max && max && max <= 3
          case max
          when 1
            success, value = parslet.apply(source, context, consume_all)
            return success ? succ([tag, value]) : context.err_at(self, source, @error_msg, source.bytepos, [value])
          when 2
            success, v1 = parslet.apply(source, context, false)
            return context.err_at(self, source, @error_msg, source.bytepos, [v1]) unless success
            success, v2 = parslet.apply(source, context, consume_all)
            return success ? succ([tag, v1, v2]) : context.err_at(self, source, @error_msg, source.bytepos, [v2])
          when 3
            success, v1 = parslet.apply(source, context, false)
            return context.err_at(self, source, @error_msg, source.bytepos, [v1]) unless success
            success, v2 = parslet.apply(source, context, false)
            return context.err_at(self, source, @error_msg, source.bytepos, [v2]) unless success
            success, v3 = parslet.apply(source, context, consume_all)
            return success ? succ([tag, v1, v2, v3]) : context.err_at(self, source, @error_msg, source.bytepos, [v3])
          end
        end

        # General case
        start_pos = source.bytepos
        occ = 0
        result = [tag]
        break_on = nil

        loop do
          success, value = parslet.apply(source, context, false)
          break_on = value
          break unless success

          occ += 1
          result << value
          break if max && occ >= max
        end

        if occ < min
          source.bytepos = start_pos
          return context.err_at(self, source, @error_msg, start_pos, [break_on])
        end

        if consume_all && source.chars_left > 0
          return context.err(self, source, @unconsumed_msg, [break_on])
        end

        succ(result)
      end
    end
  end
end
