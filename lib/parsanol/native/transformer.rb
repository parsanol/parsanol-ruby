# frozen_string_literal: true

module Parsanol
  module Native
    # Transforms native AST format to Parslet-compatible format
    #
    # Native format from Rust parser:
    #   - Slices: Parsanol::Slice objects (with position info)
    #   - Sequences: [":sequence", item1, item2, ...]
    #   - Repetitions: [":repetition", item1, item2, ...]
    #   - Named captures: {"name" => value}
    #
    # Parslet format:
    #   - Slices: Preserved as Parsanol::Slice (with position info)
    #   - Sequences: merged hash {:key1 => val1, :key2 => val2, ...}
    #   - Repetitions: array of items (or joined Slices if all are Slices)
    #   - Named wrapping Repetition: {:name => [{:name => item1}, {:name => item2}, ...]}
    #
    class AstTransformer
      # Frozen string constants for tag comparisons (avoid allocations)
      SEQUENCE_TAG = ":sequence"
      REPETITION_TAG = ":repetition"
      EMPTY_STRING = ""
      EMPTY_ARRAY = [].freeze
      EMPTY_HASH = {}.freeze

      # Symbol cache to avoid repeated string-to-symbol conversions
      # This is a class variable to share across all transformations
      @@symbol_cache = {}

      # Symbol tags from native parser
      SEQUENCE_SYM = :sequence
      REPETITION_SYM = :repetition
      MAYBE_SYM = :maybe
      MAYBE_TAG = ":maybe"

      # `named` mirrors CanFlatten#flatten's named flag: inside a Named
      # result (.as), an absent maybe flattens to nil; unnamed it flattens
      # to "".
      def self.transform(ast, named: false)
        case ast
        when Array
          transform_array(ast, named: named)
        when Hash
          transform_hash(ast)
        else
          ast
        end
      end

      # Batch transformation for multiple ASTs
      # Provides better cache locality than transforming individually
      def self.transform_batch(asts)
        asts.map { |ast| transform(ast) }
      end

      # Convert string key to symbol with caching
      def self.cached_symbol(key)
        return key if key.is_a?(Symbol)

        @@symbol_cache[key] ||= key.to_sym
      end

      def self.transform_array(arr, named: false)
        return EMPTY_ARRAY if arr.empty? # Match Parsanol Ruby mode behavior

        # Check if this is a tagged array from native parser
        # Native parser produces Symbol tags: [:sequence, item1, item2, ...]
        first = arr.first
        if [SEQUENCE_SYM, SEQUENCE_TAG].include?(first)
          # Optimized: transform items starting from index 1
          # Avoid creating arr[1..] slice
          len = arr.length
          return EMPTY_ARRAY if len == 1

          items = Array.new(len - 1)
          i = 0
          while i < len - 1
            items[i] = transform(arr[i + 1])
            i += 1
          end
          flatten_sequence(items)
        elsif [REPETITION_SYM, REPETITION_TAG].include?(first)
          # Optimized: transform items starting from index 1
          len = arr.length
          # Empty repetition: named → [], unnamed → "" (CanFlatten#flatten_repetition)
          return (named ? EMPTY_ARRAY : EMPTY_STRING) if len == 1

          items = Array.new(len - 1)
          i = 0
          while i < len - 1
            items[i] = transform(arr[i + 1])
            i += 1
          end
          flatten_repetition(items, named: named)
        elsif [MAYBE_SYM, MAYBE_TAG].include?(first)
          # Maybe flattens to nil-or-value (named) or ""-or-value (unnamed),
          # never to an array
          len = arr.length
          if len == 1
            named ? nil : EMPTY_STRING
          else
            flattened = transform(arr[1])
            named ? flattened : (flattened || EMPTY_STRING)
          end
        elsif first.is_a?(Symbol) || (first.is_a?(String) && first.start_with?(":"))
          # Other tagged arrays - pass through
          arr.map { |item| transform(item) }
        else
          # Untagged arrays from native parser are SEQUENCES
          # Apply flatten_sequence to get Parslet-compatible output
          items = arr.map { |item| transform(item) }
          flatten_sequence(items)
        end
      end

      def self.transform_hash(hash)
        # Fast path: single-key hash (99.9% of cases from native parser)
        # Native parser always produces single-key hashes: {"name" => value}
        return transform_single_key_hash(hash) if hash.length == 1

        # Slow path: multi-key hash (rare, from nested structures)
        transform_multi_key_hash(hash)
      end

      # Optimized handling for single-key hashes (the common case)
      def self.transform_single_key_hash(hash)
        # Extract the single key-value pair without iteration
        key = hash.keys.first
        value = hash[key]
        sym_key = cached_symbol(key)

        # Transform the value
        transformed = transform(value, named: true)

        # Check if value is a tagged repetition from native parser.
        # The Rust handle path tags with Symbols, the batch decoder with
        # ":repetition" Strings — accept both.
        is_tagged_repetition = value.is_a?(Array) && !value.empty? &&
          [REPETITION_SYM, REPETITION_TAG].include?(value.first)

        # Check RAW value for repetition pattern BEFORE transformation
        # Array with items that all have the parent key
        # e.g., [{x: 1}, {x: 2}] where parent key is :x
        is_raw_array_repetition = value.is_a?(Array) && !value.empty? &&
          value.all? do |item|
            item.is_a?(Hash) && item.keys.length == 1 && item.key?(key)
          end

        # Empty array from native parser is a repetition result (not a sequence)
        # Sequences produce arrays of arrays like [[], []], not empty arrays
        is_empty_repetition = value.is_a?(Array) && value.empty?

        # Special handling for arrays that look like character repetitions
        # (arrays of single-character Slices/strings should be joined)
        if transformed.is_a?(Array) && !transformed.empty? &&
            transformed.all? do |item|
              slice_or_string?(item) && item_length(item) == 1
            end
          # Join preserving position from first Slice
          first_slice = transformed.find { |i| i.is_a?(::Parsanol::Slice) }
          content = transformed.map { |i| slice_content(i) }.join
          transformed = if first_slice
                          ::Parsanol::Slice.new(first_slice.offset, content,
                                                first_slice.input)
                        else
                          content
                        end
        end

        # Check for UNTAGGED repetition pattern (native output):
        # If array items all have the same key as parent, it's a repetition
        is_transformed_repetition = transformed.is_a?(Array) && !transformed.empty? &&
          transformed.all? do |item|
            item.is_a?(Hash) && item.keys.length == 1 && item.key?(sym_key)
          end

        is_repetition = is_tagged_repetition || is_raw_array_repetition || is_transformed_repetition || is_empty_repetition

        # Handle based on type
        if is_repetition
          transform_repetition_value(sym_key, transformed)
        elsif transformed.is_a?(Hash)
          { sym_key => transformed }
        elsif transformed.is_a?(Array)
          transform_array_value(sym_key, transformed)
        else
          # Simple value (Slice, string, nil, etc.) - most common case
          { sym_key => transformed }
        end
      end

      # Get content from Slice or string
      def self.slice_content(value)
        value.is_a?(::Parsanol::Slice) ? value.content : value.to_s
      end

      # Get length of Slice or string
      def self.item_length(value)
        value.is_a?(::Parsanol::Slice) ? value.length : value.to_s.length
      end

      # Handle repetition values (named wrapping repetition)
      def self.transform_repetition_value(sym_key, transformed)
        if transformed.is_a?(Array)
          # Empty array from repetition stays as empty array
          if transformed.empty?
            { sym_key => EMPTY_ARRAY }
          # Hash items already carry their own capture names — a
          # repetition of named captures keeps them as-is (parslet
          # semantics); only unnamed items get the parent name per item.
          elsif transformed.all?(Hash)
            { sym_key => transformed }
          else
            { sym_key => transformed.map { |item| { sym_key => item } } }
          end
        elsif transformed.is_a?(::Parsanol::Slice) && transformed.empty?
          { sym_key => EMPTY_ARRAY } # Empty repetition should be [], not empty Slice
        elsif transformed.is_a?(String) && transformed == EMPTY_STRING
          { sym_key => EMPTY_ARRAY } # Empty repetition should be [], not ""
        else
          { sym_key => transformed }
        end
      end

      # Handle array values (non-repetition case)
      def self.transform_array_value(sym_key, transformed)
        if transformed.empty?
          # For empty arrays, we need to determine if this is a repetition or sequence
          # Repetitions should return [], sequences should return empty Slice
          # We can't tell from the value alone, so we return empty Slice (sequence semantics)
          # The repetition detection in transform_single_key_hash will handle the other case
          { sym_key => ::Parsanol::Slice.new(0, EMPTY_STRING, nil) }
        elsif transformed.all? do |v|
          v.is_a?(Hash) && v.keys.length == 1 && v.key?(sym_key)
        end
          # Items already have the parent key (repetition pattern) - keep as-is
          { sym_key => transformed }
        elsif transformed.all?(Hash)
          # Items are hashes with DIFFERENT keys (not the parent key)
          # This is a repetition result from (separator >> item).repeat pattern
          # The items already have their correct structure, DON'T wrap them
          # Example: [{name: "b"}, {name: "c"}] for (str(',') >> item).repeat.as(:rest)
          { sym_key => transformed }
        else
          { sym_key => transformed }
        end
      end

      # Slow path: multi-key hash (rare)
      def self.transform_multi_key_hash(hash)
        result = {}

        hash.each do |key, value|
          sym_key = cached_symbol(key)

          is_repetition = value.is_a?(Array) && !value.empty? &&
            value.first.is_a?(String) && value.first == REPETITION_TAG

          transformed = transform(value, named: true)

          result[sym_key] = if is_repetition
                              if transformed.is_a?(Array)
                                if transformed.all? do |item|
                                  item.is_a?(Hash) && item.key?(sym_key)
                                end
                                  transformed
                                else
                                  transformed.map { |item| { sym_key => item } }
                                end
                              elsif transformed == EMPTY_STRING
                                EMPTY_STRING
                              else
                                transformed
                              end
                            elsif transformed.is_a?(Hash)
                              transformed
                            elsif transformed.is_a?(Array)
                              if transformed.empty?
                                EMPTY_ARRAY
                              elsif transformed.all?(Hash)
                                transformed.map { |item| { sym_key => item } }
                              else
                                transformed
                              end
                            else
                              transformed
                            end
        end

        result
      end

      # Exact port of Parslet::Atoms::CanFlatten#flatten_sequence /
      # #merge_fold / #flatten_repetition / #foldl. Heuristic single-pass
      # rewrites diverged from this (parsanol-ruby#83); stay byte-for-byte
      # with parslet's fold.
      def self.foldl(list, &)
        return EMPTY_STRING if list.empty?

        list[1..].inject(list.first, &)
      end

      def self.flatten_sequence(items)
        foldl(items.compact) { |acc, item| merge_fold(acc, item) }
      end

      # Parslet compares exact classes (`left.class == right.class`) and
      # uses `instance_of?` below — not `is_a?` — so Slice subclasses and
      # Hash subclasses do not take the wrong branch.
      def self.merge_fold(left, right)
        # rubocop:disable Style/ClassEqualityComparison
        if left.class == right.class
          # rubocop:enable Style/ClassEqualityComparison
          return left.is_a?(Hash) ? left.merge(right) : left + right
        end

        if left.respond_to?(:to_str) && right.respond_to?(:to_str)
          return right if right.respond_to?(:to_slice)
          return left if left.respond_to?(:to_slice)

          return left.to_str + right.to_str
        end

        return left if right.respond_to?(:to_str)
        return right if left.respond_to?(:to_str)

        return left + [right] if right.is_a?(Hash)
        return [left] + right if left.is_a?(Hash)

        # Fallback: hoist both sides into an array (defensive; parslet
        # raises here, but native trees can carry nested Arrays that
        # parslet would already have folded).
        Array(left) + Array(right)
      end

      # Exact port of Parslet::Atoms::CanFlatten#flatten_repetition.
      # `named` is true only when this repetition is the direct child of
      # a Named (.as(...)); it controls empty-list folding ([] vs "").
      # `instance_of?` (not `is_a?`/`any?(Hash)`) matches parslet.
      def self.flatten_repetition(items, named: false)
        # rubocop:disable Style/PredicateWithKind
        if items.any? { |e| e.instance_of?(Hash) }
          return items.select { |e| e.instance_of?(Hash) }
        end

        if items.any? { |e| e.instance_of?(Array) }
          return items.select { |e| e.instance_of?(Array) }.flatten(1)
        end
        # rubocop:enable Style/PredicateWithKind

        return EMPTY_ARRAY if named && items.empty?

        foldl(items.compact) { |acc, item| acc + item }
      end

      # Check if value is a Slice or String
      def self.slice_or_string?(value)
        value.is_a?(::Parsanol::Slice) || value.is_a?(String)
      end
    end

    private_constant :AstTransformer
  end
end
