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
      SEQUENCE_TAG = ':sequence'
      REPETITION_TAG = ':repetition'
      EMPTY_STRING = ''
      EMPTY_ARRAY = [].freeze
      EMPTY_HASH = {}.freeze

      # Symbol cache to avoid repeated string-to-symbol conversions
      # This is a class variable to share across all transformations
      @@symbol_cache = {}

      def self.transform(ast)
        case ast
        when Array
          transform_array(ast)
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

      def self.transform_array(arr)
        return EMPTY_ARRAY if arr.empty? # Match Parsanol Ruby mode behavior

        # Check if this is a tagged array from native parser
        first = arr.first
        if first.is_a?(String) && first.start_with?(':')
          if first == SEQUENCE_TAG
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
          elsif first == REPETITION_TAG
            # Optimized: transform items starting from index 1
            len = arr.length
            return EMPTY_ARRAY if len == 1

            items = Array.new(len - 1)
            i = 0
            while i < len - 1
              items[i] = transform(arr[i + 1])
              i += 1
            end
            flatten_repetition(items)
          else
            arr.map { |item| transform(item) }
          end
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

        # Check if value is a tagged repetition from native parser
        is_tagged_repetition = value.is_a?(Array) && !value.empty? &&
                               value.first.is_a?(String) && value.first == REPETITION_TAG

        # Check RAW value for repetition pattern BEFORE transformation
        # Array with items that all have the parent key
        # e.g., [{x: 1}, {x: 2}] where parent key is :x
        is_raw_array_repetition = value.is_a?(Array) && !value.empty? &&
                                  value.all? { |item| item.is_a?(Hash) && item.keys.length == 1 && item.key?(key) }

        # Empty array from native parser is a repetition result (not a sequence)
        # Sequences produce arrays of arrays like [[], []], not empty arrays
        is_empty_repetition = value.is_a?(Array) && value.empty?

        # Transform the value
        transformed = transform(value)

        # Special handling for arrays that look like character repetitions
        # (arrays of single-character Slices/strings should be joined)
        if transformed.is_a?(Array) && !transformed.empty? &&
           transformed.all? { |item| slice_or_string?(item) && item_length(item) == 1 }
          # Join preserving position from first Slice
          first_slice = transformed.find { |i| i.is_a?(::Parsanol::Slice) }
          content = transformed.map { |i| slice_content(i) }.join
          transformed = if first_slice
                          ::Parsanol::Slice.new(first_slice.offset, content, first_slice.position_cache)
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
          # Check if items already have the same key (avoid double-wrapping)
          elsif transformed.all? { |item| item.is_a?(Hash) && item.key?(sym_key) }
            { sym_key => transformed }
          else
            # Wrap each item with the name
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
        elsif transformed.all? { |v| v.is_a?(Hash) && v.keys.length == 1 && v.key?(sym_key) }
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

          transformed = transform(value)

          result[sym_key] = if is_repetition
                              if transformed.is_a?(Array)
                                if transformed.all? { |item| item.is_a?(Hash) && item.key?(sym_key) }
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

      # Flatten sequence items according to Parslet semantics:
      # 1. If ALL items are hashes, return as array (this is a repetition result)
      # 2. If there are named captures (hashes) among Slices/strings, return ONLY the merged hash (discard Slices/strings)
      # 3. If only Slices/strings, join them preserving position from first Slice
      # 4. Return single value if only one item
      #
      # This matches Parslet's behavior where:
      #   str('SCHEMA') >> str(' ') >> match('[a-z]').repeat(1).as(:name) >> str(';')
      #   returns: {:name => "test"}  (not ["SCHEMA ", {:name=>"test"}, ";"])
      #
      # But for repetitions with named captures:
      #   match('[a-z]').as(:x).repeat(2)
      #   returns: [{:x => "a"}, {:x => "b"}]  (array of hashes, NOT merged!)
      #
      # Optimized: Single-pass with direct result building
      def self.flatten_sequence(items)
        return EMPTY_ARRAY if items.empty? # Match Parsanol Ruby mode

        # DON'T unwrap single items - let the caller handle this
        # This preserves repetition results like [{:x => 1}]
        return items if items.length == 1

        # Single pass: categorize items
        merged_hash = {}
        slice_or_string_parts = []
        hash_count = 0
        total_items = 0
        has_non_empty_array = false

        items.each do |item|
          case item
          when Hash
            merged_hash.merge!(item)
            hash_count += 1
            total_items += 1
          when ::Parsanol::Slice, String
            slice_or_string_parts << item
            total_items += 1
          when Array
            # Check if this is a non-empty array (repetition result with content)
            # Parslet behavior: when a sequence contains a non-empty repetition,
            # the WHOLE sequence should be kept as array, not merged.
            if item.empty?
              # Empty repetition - skip (sequence semantics: merge rest)
            else
              # Non-empty repetition - mark that we should keep as array
              has_non_empty_array = true
              # Still collect items for potential array result
              item.each do |sub_item|
                case sub_item
                when Hash
                  hash_count += 1
                when ::Parsanol::Slice, String
                  slice_or_string_parts << sub_item
                end
              end
            end
            total_items += 1
          when nil
            # Skip nil values (from lookahead or optional that didn't match)
          else
            total_items += 1
          end
        end

        # PARSLET SEQUENCE BEHAVIOR WITH REPETITIONS:
        # If the sequence contains a non-empty repetition result (array with items),
        # return as array instead of merging.
        # Example: factor.as(:left) >> (op >> factor).as(:rhs).repeat
        # With input "a+b" produces: [{left: {...}}, {rhs: {...}}]
        # With input "a" produces: {left: {...}} (empty repetition, merge)
        if has_non_empty_array
          # Flatten the items: top-level hashes + array items
          result = []
          items.each do |item|
            case item
            when Hash
              result << item
            when Array
              result.concat(item)
            when ::Parsanol::Slice, String
              # Skip unnamed Slices/strings when we have named captures
            end
          end
          return result.length == 1 ? result.first : result
        end

        # KEY INSIGHT: If ALL items are hashes, we need to determine:
        # 1. WRAPPER PATTERN: All hashes have the SAME single key, and values are HASHES
        #    => Merge the inner hashes under that key
        #    Example: [{:syntax => {:spaces => {...}}},
        #              {:syntax => {:schemaDecl => [...]}}]
        #    Result: {:syntax => {:spaces => {...}, :schemaDecl => [...]}}
        #
        # 2. REPETITION PATTERN: All hashes have the SAME single key, but values are SIMPLE
        #    => Keep as array (this is a repetition result)
        #    Example: [{:letter => "a"}, {:letter => "b"}, {:letter => "c"}]
        #    Result: [{:letter => "a"}, {:letter => "b"}, {:letter => "c"}]
        #
        # 3. MIXED KEYS: Hashes have DIFFERENT keys
        #    => Keep as array
        #    Example: [{:a => 1}, {:b => 2}]
        #    Result: [{:a => 1}, {:b => 2}]
        if hash_count == total_items && hash_count > 1
          # Check if all hashes have the same single key
          first_item = items.first
          if first_item.is_a?(Hash) && first_item.keys.length == 1
            wrapper_key = first_item.keys.first

            # Verify all items are hashes with the same single key
            all_same_wrapper = items.all? do |item|
              item.is_a?(Hash) && item.keys.length == 1 && item.keys.first == wrapper_key
            end

            if all_same_wrapper
              # Check if values are all hashes (wrapper pattern) or not (repetition pattern)
              all_values_are_hashes = items.all? do |item|
                item[wrapper_key].is_a?(Hash)
              end

              return items unless all_values_are_hashes

              # Wrapper pattern: merge the inner hashes
              merged_inner = {}
              items.each do |item|
                inner_value = item[wrapper_key]
                merged_inner.merge!(inner_value)
              end
              return { wrapper_key => merged_inner }

              # Repetition pattern: keep as array

            end
          end

          # MIXED KEYS: Hashes have different keys
          # Parslet sequence semantics: merge into single hash
          return merged_hash
        end

        # PARSLET SEQUENCE SEMANTICS:
        # If there are named captures (hashes) mixed with other things,
        # return ONLY the merged hash (discard unnamed Slices/strings)
        return merged_hash unless merged_hash.empty?

        # No named captures - handle Slices/strings and other items
        if slice_or_string_parts.any?
          # Join Slices/strings, preserving position from first Slice
          first_slice = slice_or_string_parts.find { |i| i.is_a?(::Parsanol::Slice) }
          content = slice_or_string_parts.map { |i| i.is_a?(::Parsanol::Slice) ? i.content : i }.join

          if first_slice
            # Create new Slice with combined content, preserving position from first
            ::Parsanol::Slice.new(first_slice.offset, content, first_slice.position_cache)
          else
            # All plain strings (shouldn't happen with new decode_flat, but handle it)
            slice_or_string_parts.length == 1 ? slice_or_string_parts.first : content
          end
        end

        # Only other items (arrays, etc.)
        return EMPTY_ARRAY if total_items.zero?

        items.length == 1 ? items.first : items
      end

      # Parslet/Parsanol repetition semantics:
      # 1. Return [] for empty repetitions
      # 2. If all items are Slices (or strings), join them preserving position
      # 3. Otherwise return array
      def self.flatten_repetition(items)
        return EMPTY_ARRAY if items.empty?

        # Single-pass flatten and check
        flat_items = []
        all_slices_or_strings = true

        items.each do |item|
          if item.is_a?(Array)
            item.each do |sub|
              flat_items << sub
              all_slices_or_strings = false unless slice_or_string?(sub)
            end
          else
            flat_items << item
            all_slices_or_strings = false unless slice_or_string?(item)
          end
        end

        return EMPTY_ARRAY if flat_items.empty?

        # If all Slices or strings, join them preserving position from first Slice
        if all_slices_or_strings
          first_slice = flat_items.find { |i| i.is_a?(::Parsanol::Slice) }
          content = flat_items.map { |i| i.is_a?(::Parsanol::Slice) ? i.content : i }.join

          if first_slice
            # Create new Slice with combined content, preserving position from first
            ::Parsanol::Slice.new(first_slice.offset, content, first_slice.position_cache)
          else
            # All plain strings (shouldn't happen with new decode_flat, but handle it)
            content
          end
        else
          flat_items
        end
      end

      # Check if value is a Slice or String
      def self.slice_or_string?(value)
        value.is_a?(::Parsanol::Slice) || value.is_a?(String)
      end
    end

    private_constant :AstTransformer
  end
end
