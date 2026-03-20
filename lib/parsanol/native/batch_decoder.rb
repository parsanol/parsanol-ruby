# frozen_string_literal: true

require 'parsanol/native/transformer'

module Parsanol
  module Native
    # Decodes flat u64 arrays from Rust batch parser into Ruby AST
    #
    # The batch format uses tagged u64 values:
    # - 0x00 = nil
    # - 0x01 + value = bool (0 or 1)
    # - 0x02 + value = int
    # - 0x03 + bits = float (IEEE 754 bits)
    # - 0x04 + offset + length = input string reference
    # - 0x05 ... 0x06 = array (start ... end)
    # - 0x07 ... 0x08 = hash (start ... end)
    # - 0x09 + len + data... = hash key
    # - 0x0A + len + data... = inline string
    module BatchDecoder
      TAG_NIL = 0x00
      TAG_BOOL = 0x01
      TAG_INT = 0x02
      TAG_FLOAT = 0x03
      TAG_STRING = 0x04
      TAG_ARRAY_START = 0x05
      TAG_ARRAY_END = 0x06
      TAG_HASH_START = 0x07
      TAG_HASH_END = 0x08
      TAG_HASH_KEY = 0x09
      TAG_INLINE_STRING = 0x0A

      class << self
        # Decode a flat u64 array into Ruby AST with Slice objects
        #
        # @param data [Array<Integer>] Flat u64 array from batch parser
        # @param input [String] Original input string (for Slice references)
        # @param slice_class [Class] The Slice class to use
        # @return [Object] Ruby AST (Hash, Array, Slice, etc.)
        def decode(data, input, slice_class)
          @input = input
          @input_bytes = input.b
          @slice_class = slice_class
          @pos = 0
          @data = data
          decode_value
        end

        # Decode and flatten - transforms raw AST to match Ruby parser output
        # This is the fast path that avoids FFI transformation overhead
        #
        # @param data [Array<Integer>] Flat u64 array from batch parser
        # @param input [String] Original input string (for Slice references)
        # @param slice_class [Class] The Slice class to use
        # @param grammar_atom [Parsanol::Atoms::Base] The grammar atom (unused, kept for API compat)
        # @return [Object] Transformed Ruby AST
        def decode_and_flatten(data, input, slice_class, grammar_atom)
          raw_ast = decode(data, input, slice_class)

          # Apply AstTransformer to convert native AST format to Parslet-compatible format
          # This handles sequence merging, repetition flattening, etc.
          # The transformer produces final format, so no additional flatten is needed.
          AstTransformer.transform(raw_ast)
        end

        # Join consecutive Slice objects in arrays into single Slices
        # This matches what transform_ast does in Rust (join_slices_from_array)
        #
        # @param value [Object] AST value
        # @param slice_class [Class] The Slice class to check for
        # @param input [String] Original input string
        # @return [Object] AST with joined slices
        def join_consecutive_slices(value, slice_class, input)
          input_bytes = input.b

          case value
          when Array
            # Recursively process array elements
            processed = value.map { |v| join_consecutive_slices(v, slice_class, input) }

            # Check if all non-nil elements are Slices
            non_nil = processed.compact
            if non_nil.all? { |v| v.is_a?(slice_class) }
              # Check if slices are consecutive
              if slices_consecutive?(non_nil)
                # Join into single slice
                join_slices(non_nil, slice_class, input_bytes, input)
              else
                processed
              end
            else
              processed
            end
          when Hash
            # Process hash values recursively
            result = {}
            value.each do |k, v|
              result[k] = join_consecutive_slices(v, slice_class, input)
            end
            result
          else
            value
          end
        end

        private

        def slices_consecutive?(slices)
          return true if slices.empty?

          slices.each_cons(2).all? do |a, b|
            a.offset + a.content.bytesize == b.offset
          end
        end

        def join_slices(slices, slice_class, input_bytes, input)
          return nil if slices.empty?
          return slices.first if slices.length == 1

          first = slices.first
          last = slices.last
          total_length = last.offset + last.content.bytesize - first.offset
          content = input_bytes[first.offset, total_length]
          content = content.force_encoding('UTF-8') if content
          slice_class.new(first.offset, content, input)
        end

        def decode_value
          tag = @data[@pos]
          @pos += 1

          case tag
          when TAG_NIL
            nil
          when TAG_BOOL
            val = @data[@pos]
            @pos += 1
            val != 0
          when TAG_INT
            val = @data[@pos]
            @pos += 1
            # Handle negative numbers (signed i64 stored as u64)
            if val >= 0x8000_0000_0000_0000
              val = val - 0x1_0000_0000_0000_0000
            end
            val
          when TAG_FLOAT
            bits = @data[@pos]
            @pos += 1
            # Convert IEEE 754 bits to float
            [bits].pack('Q').unpack1('D')
          when TAG_STRING
            offset = @data[@pos]
            length = @data[@pos + 1]
            @pos += 2
            create_slice(offset, length)
          when TAG_ARRAY_START
            decode_array
          when TAG_HASH_START
            decode_hash
          else
            raise "Unknown tag: #{tag} at position #{@pos - 1}"
          end
        end

        def decode_array
          result = []
          loop do
            tag = @data[@pos]
            break if tag == TAG_ARRAY_END

            result << decode_value
          end
          @pos += 1 # consume TAG_ARRAY_END
          result
        end

        def decode_hash
          result = {}
          loop do
            tag = @data[@pos]
            break if tag == TAG_HASH_END

            # Read key
            raise "Expected TAG_HASH_KEY, got #{tag}" unless tag == TAG_HASH_KEY
            @pos += 1
            key = decode_inline_string

            # Read value
            value = decode_value

            # Keep original key format (camelCase) for Ruby parser compatibility
            result[key.to_sym] = value
          end
          @pos += 1 # consume TAG_HASH_END
          result
        end

        def decode_inline_string
          len = @data[@pos]
          @pos += 1

          # Read u64 chunks
          chunks = (len + 7) / 8
          bytes = String.new(encoding: 'ASCII-8BIT', capacity: len)
          chunks.times do
            chunk = @data[@pos]
            @pos += 1
            8.times do |byte_idx|
              break if bytes.bytesize >= len
              bytes << ((chunk >> (byte_idx * 8)) & 0xFF)
            end
          end

          bytes.force_encoding('UTF-8')
        end

        def create_slice(offset, length)
          content = @input_bytes[offset, length]
          content = content.force_encoding('UTF-8') if content
          @slice_class.new(offset, content, @input)
        end
      end
    end
  end
end
