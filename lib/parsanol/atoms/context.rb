# frozen_string_literal: true

module Parsanol
  module Atoms
    # Parsing context that coordinates memoization caching, error reporting,
    # and resource pooling. Created fresh for each parse operation.
    #
    # Key responsibilities:
    # - Packrat-style memoization (caching parse results by position+atom)
    # - Pluggable error reporting through reporter interface
    # - Object pooling for arrays and buffers to reduce GC pressure
    # - Adaptive caching based on input size
    #
    # @example Basic usage
    #   ctx = Context.new(reporter)
    #   result = ctx.try_with_cache(parser, source, true)
    #
    # Inspired by packrat parsing memoization and incremental parsing techniques.
    #
    class Context
      # Per-parser cache size thresholds based on profiling different grammar types
      # Different grammars benefit from caching at different input sizes
      PARSER_CACHE_LIMITS = {
        "JsonParser" => 10_000,      # JSON needs large inputs to benefit
        "ErbParser" => 800,          # ERB benefits earlier
        "CalcParser" => 2000,        # Calculator has low repetition
        "SentenceParser" => 5000,    # Linear grammar, minimal benefit
        :default => 1000,
      }.freeze

      # Creates a new parsing context.
      #
      # @param error_reporter [#err, #err_at] error reporter instance
      # @param interval_cache: [Boolean] enable GPeg-style interval caching
      # @param adaptive_cache_threshold: [Integer, nil] minimum input size for caching
      # @param parser_class: [Class, nil] parser class for threshold selection
      #
      def initialize(error_reporter = Parsanol::ErrorReporter::Tree.new,
                     interval_cache: false,
                     adaptive_cache_threshold: nil,
                     parser_class: nil)
        # Core memoization cache: position -> { atom_id -> [result, advance] }
        @memo = Hash.new { |h, k| h[k] = {} }

        # Error reporting delegate
        @reporter = error_reporter

        # Capture scope for variable bindings
        @captures = Parsanol::Scope.new

        # Cache eviction state
        @furthest_pos = 0
        @evict_threshold = 200
        @evict_counter = 0
        @evict_interval = 100

        # Object pools for reducing allocations
        @array_pool = Parsanol::Pools::ArrayPool.new(size: 10_000)
        @buffer_pool = Parsanol::Pools::BufferPool.new(pool_size: 100)

        # Selective memoization tracking
        @hit_stats = Hash.new(0)
        @miss_stats = Hash.new(0)
        @min_hits_for_cache = 2

        # Optional GPeg-style interval caching
        @use_intervals = interval_cache
        if @use_intervals
          require "parsanol/interval_tree"
          require "parsanol/edit_tracker"
          @interval_trees = Hash.new { |h, k| h[k] = Parsanol::IntervalTree.new }
          @edits = Parsanol::EditTracker.new
        end

        # Cut operator support for aggressive eviction
        @cut_pos = 0

        # Determine adaptive cache threshold
        threshold = adaptive_cache_threshold
        if threshold.nil? && parser_class
          name = parser_class.name&.split("::")&.last
          threshold = PARSER_CACHE_LIMITS[name] || PARSER_CACHE_LIMITS[:default]
        end
        threshold ||= PARSER_CACHE_LIMITS[:default]

        @adaptive_threshold = threshold
        @input_len = nil
        @caching_active = nil
      end

      # Attempts to parse using memoization. Returns cached result if available,
      # otherwise executes the parser and caches the result.
      #
      # @param atom [Parsanol::Atoms::Base] parser to apply
      # @param src [Parsanol::Source] input source
      # @param must_consume_all [Boolean] require complete consumption
      # @return [Array(Boolean, Object)] parse result tuple
      #
      def try_with_cache(atom, src, must_consume_all)
        # Skip caching for atoms that don't benefit from it
        return atom.try(src, self, must_consume_all) unless atom.cached?

        # Determine if caching should be active (lazy initialization)
        if @caching_active.nil?
          total_len = src.bytepos + src.chars_left
          @input_len = total_len
          @caching_active = total_len >= @adaptive_threshold
        end

        # For small inputs, skip caching overhead
        return atom.try(src, self, must_consume_all) unless @caching_active

        # Use interval-based caching if enabled
        return try_with_interval(atom, src, must_consume_all) if @use_intervals

        pos = src.bytepos
        key = atom.object_id

        # Periodic cache eviction to prevent unbounded growth
        if pos > @furthest_pos
          @furthest_pos = pos
          @evict_counter += 1

          if @evict_counter >= @evict_interval
            @evict_counter = 0
            cutoff = pos - @evict_threshold
            @memo.delete_if { |p, _| p < cutoff }
          end
        end

        # Check for cache hit
        if @memo[pos].key?(key)
          @hit_stats[key] += 1
          outcome, delta = @memo[pos][key]
          src.bytepos = pos + delta
          return outcome
        end

        # Cache miss - execute and store
        @miss_stats[key] += 1
        outcome = atom.try(src, self, must_consume_all)
        delta = src.bytepos - pos

        # Only cache if beneficial (heuristic)
        attempts = @hit_stats[key] + @miss_stats[key]
        if attempts <= @min_hits_for_cache || @hit_stats[key].positive?
          @memo[pos][key] =
            [outcome,
             delta]
        end

        outcome
      end

      # GPeg-style interval-based caching for incremental parsing.
      #
      # @param atom [Parsanol::Atoms::Base] parser to apply
      # @param src [Parsanol::Source] input source
      # @param must_consume_all [Boolean] require complete consumption
      # @return [Array(Boolean, Object)] parse result tuple
      #
      def try_with_interval(atom, src, must_consume_all)
        pos = src.bytepos
        key = atom.object_id

        tree = @interval_trees[key]
        cached = tree.query_exact(pos, pos)

        if cached
          @hit_stats[key] += 1
          outcome, delta = cached
          src.bytepos = pos + delta
          return outcome
        end

        @miss_stats[key] += 1
        outcome = atom.try(src, self, must_consume_all)
        delta = src.bytepos - pos
        end_pos = pos + delta

        attempts = @hit_stats[key] + @miss_stats[key]
        if attempts <= @min_hits_for_cache || @hit_stats[key].positive?
          tree.insert(pos, end_pos,
                      [outcome, delta])
        end

        outcome
      end

      # Pre-allocated result constants
      SUCCESS_RESULT = [true, nil].freeze
      ERROR_RESULT = [false, nil].freeze

      # Reports an error at a specific position.
      #
      # @return [Array(Boolean, Object)] error result tuple
      #
      def err_at(*)
        return [false, @reporter.err_at(*)] if @reporter

        ERROR_RESULT
      end

      # Reports an error at the current position.
      #
      # @return [Array(Boolean, Object)] error result tuple
      #
      def err(*)
        return [false, @reporter.err(*)] if @reporter

        ERROR_RESULT
      end

      # Reports a successful parse.
      #
      # @return [Array(Boolean, Object)] success result tuple
      #
      def succ(*)
        return SUCCESS_RESULT unless @reporter

        val = @reporter.succ(*)
        return SUCCESS_RESULT if val.nil?

        [true, val]
      end

      # @return [Parsanol::Scope] capture variable bindings
      attr_reader :captures

      # @return [Parsanol::Pools::ArrayPool] array object pool
      attr_reader :array_pool

      # @return [Parsanol::Pools::BufferPool] buffer object pool
      attr_reader :buffer_pool

      # Acquires an empty array from the pool.
      #
      # @return [Array] cleared array ready for use
      #
      def acquire_array
        @array_pool.acquire
      end

      # Returns an array to the pool for reuse.
      #
      # @param arr [Array] array to release
      # @return [Boolean] true if pooled, false if discarded
      #
      def release_array(arr)
        @array_pool.release(arr)
      end

      # Acquires a buffer with minimum capacity from the pool.
      #
      # @param size: [Integer] minimum required capacity
      # @return [Parsanol::Buffer] buffer with capacity >= size
      #
      def acquire_buffer(size:)
        @buffer_pool.acquire(size: size)
      end

      # Returns a buffer to the pool for reuse.
      #
      # @param buf [Parsanol::Buffer] buffer to release
      # @return [Boolean] true if pooled, false if discarded
      #
      def release_buffer(buf)
        @buffer_pool.release(buf)
      end

      # Creates a new capture scope for the duration of the block.
      #
      # @yield block executed in new scope
      #
      def scope
        captures.push
        yield
      ensure
        captures.pop
      end

      # Checks if interval-based caching is active.
      #
      # @return [Boolean] true if interval caching enabled
      #
      def use_tree_memoization?
        @use_intervals
      end

      # Queries interval cache for a cached result.
      #
      # @param key [Integer] cache key (atom object_id)
      # @param start_pos [Integer] starting position
      # @return [Array, nil] cached [values, end_pos] or nil
      #
      def query_tree_memo(key, start_pos)
        return nil unless @use_intervals

        tree = @interval_trees[key]
        matches = tree.query_overlapping(start_pos, start_pos + 1)
        found = matches.find { |interval, _| interval[0] == start_pos }
        found ? found[1] : nil
      end

      # Stores a result in the interval cache.
      #
      # @param key [Integer] cache key
      # @param start_pos [Integer] start position
      # @param values [Array] parsed values
      # @param end_pos [Integer] end position
      #
      def store_tree_memo(key, start_pos, values, end_pos)
        return unless @use_intervals

        @interval_trees[key].insert(start_pos, end_pos, [values, end_pos])
      end

      # Marks a cut position for aggressive cache eviction.
      # Called when a cut operator succeeds.
      #
      # @param position [Integer] cut position
      #
      def cut!(position)
        @cut_pos = position
        @memo.delete_if { |pos, _| pos < position }
      end

      private

      # Lookup cached result (uses object_id for speed)
      def lookup(atom, pos)
        @memo[pos][atom.object_id]
      end

      # Store result in cache
      def set(atom, pos, val)
        @memo[pos][atom.object_id] = val
      end
    end
  end
end
