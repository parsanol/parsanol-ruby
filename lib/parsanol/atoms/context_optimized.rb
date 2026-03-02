# frozen_string_literal: true

# Experimental: Position-based cache eviction for Context
# Based on PEG theory: in linear parsing, positions behind current position
# will never be revisited, so we can evict them to reduce memory

module Parsanol
  module Atoms
    class Context
      # Add position tracking for cache eviction
      attr_reader :current_position

      def try_with_cache(obj, source, consume_all)
        return obj.try(source, self, consume_all) unless obj.cached?

        key = source.pos
        @current_position = key
        atom_cache = @cache[obj]

        # Try to fetch from cache
        return atom_cache.fetch(key) if atom_cache.key?(key)

        # Cache miss - compute result
        result = obj.try(source, self, consume_all)
        atom_cache[key] = result

        # Evict old positions if cache is getting large
        # Keep only positions within a window of current position
        if atom_cache.size > 100
          min_pos = key - 50 # Keep 50 positions behind
          atom_cache.delete_if { |pos, _| pos < min_pos }
        end

        result
      end
    end
  end
end
