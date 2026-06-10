# frozen_string_literal: true

# Ordered choice - tries alternatives left-to-right, returning first success.
# Fails only if all alternatives fail.
#
# @example Simple choice
#   str('a') | str('b')  # matches 'a' or 'b'
#
# This is PEG ordered choice - no backtracking to later alternatives.
#
module Parsanol
  module Atoms
    class Alternative < Parsanol::Atoms::Base
      INDEX_THRESHOLD = 16
      INDEX_MIN_BRANCHES = 4
      CHOICE_ERROR_DETAIL_LIMIT = 16

      # @return [Array<Parsanol::Atoms::Base>] alternative parsers
      attr_reader :alternatives

      # Creates a new choice.
      #
      # @param options [Array<Parsanol::Atoms::Base>] alternatives
      def initialize(*options)
        super()
        # Frozen so the lazily memoized literal index can never go stale:
        # the index assumes this array is immutable after construction.
        @alternatives = options.freeze
      end

      # Adds an alternative with flattening.
      #
      # @param parser [Parsanol::Atoms::Base] new alternative
      # @return [Parsanol::Atoms::Alternative] flattened choice
      def |(other)
        expanded = if other.is_a?(Parsanol::Atoms::Alternative)
                     @alternatives + other.alternatives
                   else
                     @alternatives + [other]
                   end
        self.class.new(*expanded)
      end

      # Tries each alternative in order.
      #
      # @param source [Parsanol::Source] input
      # @param context [Parsanol::Atoms::Context] context
      # @param consume_all [Boolean] require full consumption
      # @return [Array(Boolean, Object)] result
      def try(source, context, consume_all)
        options = @alternatives
        count = options.size

        # Optimized paths for common sizes
        case count
        when 2
          try_two(options[0], options[1], source, context, consume_all)
        when 3
          try_three(options[0], options[1], options[2], source, context,
                    consume_all)
        else
          try_many(options, source, context, consume_all)
        end
      end

      precedence CHOICE

      # String representation.
      #
      # @param prec [Integer] precedence
      # @return [String]
      def to_s_inner(prec)
        @alternatives.map { |a| a.to_s(prec) }.join(" / ")
      end

      # FIRST set is union of all alternatives' FIRST sets.
      #
      # @return [Set]
      def compute_first_set
        return Set.new if @alternatives.empty?

        @alternatives.map(&:first_set).reduce(&:union)
      end

      private

      # Two-alternative fast path
      def try_two(a1, a2, source, context, consume_all)
        success, value1 = a1.apply(source, context, consume_all)
        return [success, value1] if success

        success, value2 = a2.apply(source, context, consume_all)
        return [success, value2] if success

        context.err(self, source, choice_error, [value1, value2])
      end

      # Three-alternative fast path
      def try_three(a1, a2, a3, source, context, consume_all)
        success, value1 = a1.apply(source, context, consume_all)
        return [success, value1] if success

        success, value2 = a2.apply(source, context, consume_all)
        return [success, value2] if success

        success, value3 = a3.apply(source, context, consume_all)
        return [success, value3] if success

        context.err(self, source, choice_error, [value1, value2, value3])
      end

      # General case for N alternatives
      def try_many(options, source, context, consume_all)
        # The reporting pass (the re-parse after a failure) must try every
        # branch so the failure cause tree stays complete; the literal index
        # only prunes the fast non-reporting pass.
        unless context.reporting?
          indexed = indexed_options(source)
          if indexed
            return try_selected(indexed, options, source, context, consume_all)
          end
        end

        try_all(options, source, context, consume_all)
      end

      def try_all(options, source, context, consume_all)
        errors = nil

        options.each do |alt|
          success, value = alt.apply(source, context, consume_all)
          return [success, value] if success

          errors ||= []
          errors << value
        end

        context.err(self, source, choice_error, errors)
      end

      def try_selected(indexes, options, source, context, consume_all)
        errors = nil

        indexes.each do |idx|
          success, value = options[idx].apply(source, context, consume_all)
          return [success, value] if success

          errors ||= []
          errors << value
        end

        context.err(self, source, choice_error, errors)
      end

      def indexed_options(source)
        index = literal_index
        return nil unless index

        indexes = index[:always].dup
        prefixes = index[:prefixes]
        max_prefix_bytes = index[:max_prefix_bytes]
        current_prefix = +""

        valid_prefix_preview(source.peek(max_prefix_bytes)).each_char do |char|
          current_prefix << char
          matches = prefixes[current_prefix]
          indexes.concat(matches) if matches
        end

        indexes.uniq!
        indexes.sort!
        indexes
      end

      def literal_index
        return nil if @alternatives.size < INDEX_THRESHOLD

        # Benign lazy race: alternatives are frozen at initialization, so
        # concurrent builds produce the same index and the last assignment wins.
        return @literal_index if defined?(@literal_index)

        @literal_index = build_literal_index
      end

      def build_literal_index
        prefixes = {}
        always = []
        indexed_count = 0
        max_prefix_bytes = 0

        @alternatives.each_with_index do |alt, idx|
          prefix, = static_literal_prefixes(alt)

          if prefix.nil? || prefix.empty?
            always << idx
            next
          end

          add_to_index(prefixes, prefix, idx)
          indexed_count += 1
          max_prefix_bytes = [max_prefix_bytes, prefix.bytesize].max
        end

        return nil if indexed_count < INDEX_MIN_BRANCHES

        {
          prefixes: freeze_prefix_index(prefixes),
          max_prefix_bytes: max_prefix_bytes,
          always: always.freeze,
        }.freeze
      end

      def add_to_index(prefixes, prefix, idx)
        (prefixes[prefix] ||= []) << idx
      end

      def freeze_prefix_index(prefixes)
        prefixes.transform_values(&:freeze).freeze
      end

      def valid_prefix_preview(preview)
        return preview if preview.valid_encoding?

        bytesize = preview.bytesize
        while bytesize.positive?
          bytesize -= 1
          trimmed = preview.byteslice(0, bytesize)
          return trimmed if trimmed.valid_encoding?
        end

        +""
      end

      def choice_error
        @choice_error ||= if @alternatives.size <= CHOICE_ERROR_DETAIL_LIMIT
                            "Expected one of #{alternatives_inspect}"
                          else
                            "Expected one of #{@alternatives.size} alternatives"
                          end
      end

      def alternatives_inspect
        @alternatives.inspect
      rescue StandardError
        "[#{@alternatives.map { |atom| atom_inspect(atom) }.join(', ')}]"
      end

      def atom_inspect(atom)
        atom.inspect
      rescue StandardError
        atom.class.name || atom.class.to_s
      end

      # Returns [prefix, exact]. prefix is a literal string every successful
      # match of the atom is guaranteed to start with (nil when none can be
      # proven). exact is true only when the atom matches exactly that literal
      # and nothing else, so a parent sequence may keep appending literals
      # from subsequent parts. A partial prefix (exact: false) is still a
      # sound index key on its own, but nothing may be appended after it.
      def static_literal_prefixes(atom, seen = {})
        object_id = atom.object_id
        return [nil, false] if seen[object_id]

        seen[object_id] = true
        marked = true

        if atom.instance_of?(Parsanol::Atoms::Str)
          [atom.str, true]
        elsif atom.instance_of?(Parsanol::Atoms::Named)
          static_literal_prefixes(atom.parslet, seen)
        elsif atom.instance_of?(Parsanol::Atoms::Entity)
          parslet = static_entity_parslet(atom)
          parslet ? static_literal_prefixes(parslet, seen) : [nil, false]
        elsif atom.instance_of?(Parsanol::Atoms::Sequence)
          static_sequence_literal_prefixes(atom, seen)
        else
          [nil, false]
        end
      ensure
        # Only clear markers set by this frame; an early return for an already
        # seen atom must not remove an ancestor's recursion guard.
        seen.delete(object_id) if marked
      end

      def static_sequence_literal_prefixes(atom, seen)
        prefix = +""
        exact = true

        atom.parslets.each do |part|
          part_prefix, part_exact = static_literal_prefixes(part, seen)

          if part_prefix.nil?
            exact = false
            break
          end

          prefix << part_prefix

          # A partial part may match more input after its own prefix, so
          # literals from later parts are not guaranteed to follow at this
          # offset — appending them would over-claim and mis-prune branches.
          unless part_exact
            exact = false
            break
          end
        end

        return [nil, false] if prefix.empty?

        [prefix, exact]
      end

      def static_entity_parslet(atom)
        atom.parslet
      rescue StandardError, NotImplementedError
        nil
      end
    end
  end
end
