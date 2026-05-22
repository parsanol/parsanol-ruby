# frozen_string_literal: true

# Repetition - matches a parser multiple times.
# Supports min/max bounds for various quantifier patterns.
#
# @example Quantifiers
#   str('a').repeat(1,3)  # 1 to 3 'a's
#   str('a').maybe        # optional 'a' (0 or 1)
#   str('a').repeat       # zero or more
#
module Parsanol
  module Atoms
    class Repetition < Parsanol::Atoms::Base
      # @return [Integer] minimum matches required
      attr_reader :min

      # @return [Integer, nil] maximum matches allowed
      attr_reader :max

      # @return [Parsanol::Atoms::Base] repeated parser
      attr_reader :parslet

      # @return [Symbol] result tag
      attr_reader :result_tag

      # Alias for compatibility
      alias tag result_tag

      # Creates a new repetition.
      #
      # @param parser [Parsanol::Atoms::Base] parser to repeat
      # @param min_count [Integer] minimum repetitions
      # @param max_count [Integer, nil] maximum repetitions
      # @param tag [Symbol] result tag
      def initialize(parser, min_count, max_count, tag = :repetition)
        super()

        # Handle nil max_count (unbounded repetition)
        if max_count&.zero?
          raise ArgumentError, "Cannot repeat zero times: #{parser.inspect}"
        end

        @parslet = parser
        @min = min_count
        @max = max_count
        @result_tag = tag

        # Internal value for comparisons (nil becomes infinity)
        @max_internal = max_count || Float::INFINITY

        # Pre-built error messages
        @min_error = "Expected at least #{min_count} of #{parser.inspect}"
        @extra_error = "Extra input after last repetition"
      end

      # Error messages hash (for compatibility)
      def error_msgs
        { minrep: @min_error, unconsumed: @extra_error }
      end

      # Executes the repetition.
      #
      # @param source [Parsanol::Source] input
      # @param context [Parsanol::Atoms::Context] context
      # @param consume_all [Boolean] require full consumption
      # @return [Array(Boolean, Object)] result
      def try(source, context, consume_all)
        # Check for tree memoization support
        if context.respond_to?(:use_tree_memoization?) && context.use_tree_memoization?
          return with_tree_cache(source, context, consume_all)
        end

        # Maybe (0 or 1) - very common, optimize
        if @min.zero? && @max == 1
          return try_maybe(source, context,
                           consume_all)
        end

        # Exact count optimization
        if @min == @max && @max && @max <= 3
          return try_exact(source, context,
                           consume_all)
        end

        # General case
        try_general(source, context, consume_all)
      end

      precedence REPETITION

      # String representation.
      #
      # @param prec [Integer] precedence
      # @return [String]
      def to_s_inner(prec)
        suffix = if @min.zero? && @max == 1
                   "?"
                 else
                   "{#{@min}, #{@max}}"
                 end
        @parslet.to_s(prec) + suffix
      end

      # FIRST set includes EPSILON if min == 0.
      #
      # @return [Set]
      def compute_first_set
        first = @parslet.first_set.dup
        first.add(Parsanol::FirstSet::EPSILON) if @min.zero?
        first
      end

      private

      # Optional match (0 or 1)
      def try_maybe(source, context, _consume_all)
        success, value = @parslet.apply(source, context, false)
        return ok([@result_tag, value]) if success

        ok(@result_tag == :repetition ? Parsanol::Atoms::Base::REP_TAG : [@result_tag])
      end

      # Exact count match (1, 2, or 3)
      def try_exact(source, context, consume_all)
        case @max
        when 1
          single_match(source, context, consume_all)
        when 2
          double_match(source, context, consume_all)
        when 3
          triple_match(source, context, consume_all)
        end
      end

      def single_match(source, context, consume_all)
        success, value = @parslet.apply(source, context, consume_all)
        return ok([@result_tag, value]) if success

        context.err_at(self, source, @min_error, source.bytepos, [value])
      end

      def double_match(source, context, consume_all)
        success, v1 = @parslet.apply(source, context, false)
        unless success
          return context.err_at(self, source, @min_error, source.bytepos,
                                [v1])
        end

        success, v2 = @parslet.apply(source, context, consume_all)
        return ok([@result_tag, v1, v2]) if success

        context.err_at(self, source, @min_error, source.bytepos, [v2])
      end

      def triple_match(source, context, consume_all)
        success, v1 = @parslet.apply(source, context, false)
        unless success
          return context.err_at(self, source, @min_error, source.bytepos,
                                [v1])
        end

        success, v2 = @parslet.apply(source, context, false)
        unless success
          return context.err_at(self, source, @min_error, source.bytepos,
                                [v2])
        end

        success, v3 = @parslet.apply(source, context, consume_all)
        return ok([@result_tag, v1, v2, v3]) if success

        context.err_at(self, source, @min_error, source.bytepos, [v3])
      end

      # General repetition with buffer pooling
      def try_general(source, context, consume_all)
        start_pos = source.bytepos
        occurrence = 0

        # Estimate buffer size
        estimate = [@max || 10, 10].min
        buffer = context.acquire_buffer(size: estimate + 1)
        buffer.push(@result_tag)

        last_error = nil

        loop do
          success, value = @parslet.apply(source, context, false)
          last_error = value

          break unless success

          occurrence += 1
          buffer.push(value)

          break if @max && occurrence >= @max
        end

        # Check minimum bound
        if occurrence < @min
          context.release_buffer(buffer)
          source.bytepos = start_pos
          return context.err_at(self, source, @min_error, start_pos,
                                [last_error])
        end

        # Check complete consumption
        if consume_all && source.chars_left.positive?
          context.release_buffer(buffer)
          return context.err(self, source, @extra_error, [last_error])
        end

        ok(Parsanol::LazyResult.new(buffer, context))
      end

      # Tree memoization for GPEG-style caching
      def with_tree_cache(source, context, consume_all)
        start_pos = source.bytepos
        cache_key = object_id

        # Check cache
        cached = context.query_tree_memo(cache_key, start_pos)
        if cached
          values, end_pos = cached
          source.bytepos = end_pos
          return ok([@result_tag] + values)
        end

        # Parse and cache
        occurrence = 0
        estimate = [@max || 10, 10].min
        buffer = context.acquire_buffer(size: estimate + 1)
        buffer.push(@result_tag)

        positions = context.acquire_array
        positions << start_pos
        last_error = nil

        loop do
          source.bytepos
          success, value = @parslet.apply(source, context, false)
          last_error = value

          break unless success

          occurrence += 1
          buffer.push(value)
          positions << source.bytepos

          break if @max && occurrence >= @max
        end

        # Cache successful prefix
        if occurrence.positive?
          end_pos = positions[occurrence]
          context.store_tree_memo(cache_key, start_pos, buffer.to_a[1..],
                                  end_pos)
        end

        # Check minimum
        if occurrence < @min
          context.release_buffer(buffer)
          source.bytepos = start_pos
          return context.err_at(self, source, @min_error, start_pos,
                                [last_error])
        end

        # Check consumption
        if consume_all && source.chars_left.positive?
          context.release_buffer(buffer)
          return context.err(self, source, @extra_error, [last_error])
        end

        ok(Parsanol::LazyResult.new(buffer, context))
      end
    end
  end
end
