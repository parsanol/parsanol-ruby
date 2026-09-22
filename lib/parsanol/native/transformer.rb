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
      EMPTY_STRING = ""
      EMPTY_ARRAY = [].freeze
      EMPTY_HASH = {}.freeze

      # Symbol cache to avoid repeated string-to-symbol conversions
      # This is a class variable to share across all transformations
      @@symbol_cache = {}

      # Envelope tags. Both tiers (extension objects and the flat-u64
      # batch wire) deliver Symbols — the encoder writes ':'-prefixed
      # strings as TAG_SYMBOL — so there is exactly one tag form.
      SEQUENCE_SYM = :sequence
      REPETITION_SYM = :repetition
      MAYBE_SYM = :maybe

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
        case first
        when SEQUENCE_SYM
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
        when REPETITION_SYM
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
        when MAYBE_SYM
          # Maybe flattens to nil-or-value (named) or ""-or-value (unnamed),
          # never to an array
          len = arr.length
          if len == 1
            named ? nil : EMPTY_STRING
          else
            flattened = transform(arr[1])
            named ? flattened : (flattened || EMPTY_STRING)
          end
        when Symbol
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

      # Optimized handling for single-key hashes (the common case).
      # The shape scans below are fused into as few passes as possible:
      # each predicate was previously its own `all?` walk with a lambda
      # dispatch, and `item.keys.length` allocated a keys array per
      # element (Hash#length is O(1)).
      def self.transform_single_key_hash(hash)
        # Extract the single key-value pair without iterating (the hash
        # is guaranteed single-key by the caller).
        key, = hash.first
        value = hash[key]
        sym_key = cached_symbol(key)

        # Transform the value
        transformed = transform(value, named: true)

        # Tagged repetition from the native parser (Symbol tag; both
        # tiers deliver the same form).
        is_tagged_repetition = value.is_a?(Array) && !value.empty? &&
          value.first.equal?(REPETITION_SYM)

        # Check RAW value for repetition pattern BEFORE transformation
        # (bare repeated sibling captures, #36): array items that all
        # carry the parent key, e.g. [{x: 1}, {x: 2}].
        is_raw_array_repetition = false
        if value.is_a?(Array) && !value.empty? && !is_tagged_repetition
          is_raw_array_repetition = raw_items_all_named?(value, key)
        end

        # Empty array from native parser is a repetition result (not a sequence)
        # Sequences produce arrays of arrays like [[], []], not empty arrays
        is_empty_repetition = value.is_a?(Array) && value.empty?

        # Single fused pass over the transformed array: detect the
        # single-character join shape AND the untagged repetition shape
        # in one walk (an element cannot be both a Hash and a
        # single-character stringlike, so the predicates share a loop).
        joined = nil
        is_transformed_repetition = false
        if transformed.is_a?(Array) && !transformed.empty?
          all_named = true
          all_single_char = true
          content = nil
          first_slice = nil
          transformed.each do |item|
            if item.is_a?(Hash)
              all_single_char = false
              unless item.length == 1 && item.key?(sym_key)
                all_named = false
                break
              end
            elsif item.is_a?(::Parsanol::Slice) || item.is_a?(String)
              all_named = false
              all_single_char = false unless item.length == 1
              break if !all_single_char && !all_named
            else
              all_named = false
              all_single_char = false
              break
            end
          end

          if all_single_char
            # Join preserving position from the first Slice
            content = +""
            transformed.each do |item|
              if item.is_a?(::Parsanol::Slice)
                first_slice ||= item
                content << item.content
              else
                content << item.to_s
              end
            end
            joined = if first_slice
                       ::Parsanol::Slice.new(first_slice.offset,
                                             content, first_slice.input)
                     else
                       content
                     end
          elsif all_named
            is_transformed_repetition = true
          end
        end

        transformed = joined if joined
        is_repetition = is_tagged_repetition || is_raw_array_repetition ||
          is_transformed_repetition || is_empty_repetition

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

      # Alloc-free raw repetition scan: Hash#length instead of
      # item.keys.length (which allocated per element).
      def self.raw_items_all_named?(value, key)
        value.all? do |item|
          item.is_a?(Hash) && item.length == 1 && item.key?(key)
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
            value.first.equal?(REPETITION_SYM)

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
      # with parslet's fold. Hot shapes (all-Hash, all-stringlike)
      # short-circuit before the fold to avoid per-step allocations.
      def self.foldl(list, &)
        return EMPTY_STRING if list.empty?

        list.drop(1).inject(list.first, &)
      end

      def self.flatten_sequence(items)
        list = items.compact
        return EMPTY_STRING if list.empty?
        return list.first if list.length == 1

        # Hot path: all-hash sequence. Single-pass merge preserves
        # parslet's merge_fold(Hash, Hash) last-wins semantics.
        if list.all?(Hash)
          return list.reduce { |acc, hash| acc.merge(hash) }
        end

        # Hot path: all stringlike (String/Slice). One fused pass detects
        # the shape and joins contents in place (no per-item lambda
        # dispatch, no intermediate map array).
        content = +""
        first_slice = nil
        all_stringlike = list.all? do |x|
          if x.is_a?(::Parsanol::Slice)
            first_slice ||= x
            content << x.content
            true
          elsif x.is_a?(String)
            content << x
            true
          else
            false
          end
        end
        if all_stringlike
          return first_slice ? ::Parsanol::Slice.new(first_slice.offset, content,
                                                     first_slice.input) : content
        end

        # Cold path: parslet's exact fold (Hash/Slice/String/Array
        # mixtures, including the #83 paragraph cases).
        foldl(list) { |acc, item| merge_fold(acc, item) }
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

        # Hot path: all-stringlike repetition → fused single-pass concat.
        # Cold path: parslet's exact fold.
        if items.empty?
          return EMPTY_STRING
        end

        content = +""
        first_slice = nil
        all_stringlike = items.all? do |x|
          if x.is_a?(::Parsanol::Slice)
            first_slice ||= x
            content << x.content
            true
          elsif x.is_a?(String)
            content << x
            true
          else
            false
          end
        end
        if all_stringlike
          return first_slice ? ::Parsanol::Slice.new(first_slice.offset, content,
                                                     first_slice.input) : content
        end

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
