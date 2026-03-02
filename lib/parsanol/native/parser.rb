# frozen_string_literal: true

require 'digest'

module Parsanol
  module Native
    # Core parsing functionality using Rust native extension
    #
    # Provides three parsing modes:
    # - :ruby - Parse and transform to Parslet-compatible format
    # - :json - Parse and return JSON-serialized AST
    # - :slice - Parse and return raw native format (fastest)
    #
    module Parser
      # Two-level grammar cache (module-level for proper initialization)
      GRAMMAR_HASH_CACHE = {}.freeze  # object_id => hash_key
      GRAMMAR_CACHE = {}.freeze       # hash_key => grammar_json

      class << self
        # Cached availability check
        @cached_available = nil

        # Check if native extension is available
        def available?
          return @cached_available unless @cached_available.nil?

          @cached_available = begin
            require 'parsanol/parsanol_native'
            Parsanol::Native.is_available
          rescue LoadError
            false
          end
        end

        # Parse using native engine
        # @param grammar_json [String] JSON-serialized grammar
        # @param input [String] Input string to parse
        # @return Ruby AST from parsing
        def parse(grammar_json, input)
          raise LoadError, 'Native parser not available. Run `rake compile` to build.' unless available?

          # Call native parse_batch (returns flat u64 array)
          flat = Parsanol::Native.parse_batch(grammar_json, input)
          # Decode flat array to Ruby AST
          decode_flat(flat, input)
        end

        # Parse a grammar with automatic serialization and caching
        # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
        # @param input [String] Input string to parse
        # @return Ruby AST from parsing
        def parse_with_grammar(root_atom, input)
          # Extract root atom if a Parser is passed
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          grammar_json = serialize_grammar(root_atom)
          parse(grammar_json, input)
        end

        # Parse and transform to Parslet-compatible format
        # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
        # @param input [String] Input string to parse
        # @return Ruby AST in Parslet-compatible format
        def parse_parslet_compatible(root_atom, input)
          # Extract root atom if a Parser is passed
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          raw_ast = parse_with_grammar(root_atom, input)
          AstTransformer.transform(raw_ast)
        end

        # Parse multiple inputs with the same grammar (more efficient)
        # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
        # @param inputs [Array<String>] Array of input strings to parse
        # @return [Array] Array of raw Ruby ASTs from parsing
        def parse_batch_inputs(root_atom, inputs)
          # Extract root atom if a Parser is passed
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          grammar_json = serialize_grammar(root_atom)
          inputs.map { |input| parse(grammar_json, input) }
        end

        # Parse multiple inputs with transformation
        # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
        # @param inputs [Array<String>] Array of input strings to parse
        # @return [Array] Array of transformed Ruby ASTs
        def parse_batch_with_transform(root_atom, inputs)
          # Extract root atom if a Parser is passed
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          grammar_json = serialize_grammar(root_atom)
          # First parse all inputs, then batch transform
          # This provides better cache locality
          raw_asts = inputs.map { |input| parse(grammar_json, input) }
          AstTransformer.transform_batch(raw_asts)
        end

        # Parse without transformation (faster for raw AST access)
        # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
        # @param input [String] Input string to parse
        # @return Raw Ruby AST from parsing (native format)
        def parse_raw(root_atom, input)
          # Extract root atom if a Parser is passed
          root_atom = root_atom.root if root_atom.is_a?(::Parsanol::Parser)
          parse_with_grammar(root_atom, input)
        end

        # Serialize a grammar to JSON, with two-level caching
        # Level 1: object_id => hash_key (avoids grammar traversal)
        # Level 2: hash_key => grammar_json (avoids serialization)
        # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
        # @return [String] JSON string
        def serialize_grammar(root_atom)
          # Level 1: Check if we've already computed the hash for this object
          obj_id = root_atom.object_id
          cache_key = GRAMMAR_HASH_CACHE[obj_id]

          if cache_key
            # Fast path: already computed hash, check grammar cache
          else
            # Slow path: compute structural hash
            cache_key = grammar_structure_hash(root_atom)
            GRAMMAR_HASH_CACHE[obj_id] = cache_key
          end
          GRAMMAR_CACHE[cache_key] ||= GrammarSerializer.serialize(root_atom)
        end

        # Clear grammar caches (call if grammar changes)
        def clear_cache
          GRAMMAR_HASH_CACHE.clear
          GRAMMAR_CACHE.clear
        end

        # Get cache statistics
        def cache_stats
          {
            hash_cache_size: GRAMMAR_HASH_CACHE.size,
            grammar_cache_size: GRAMMAR_CACHE.size,
            grammar_keys: GRAMMAR_CACHE.keys
          }
        end

        # ===== Serialized Mode (JSON Output) =====

        # Parse input and return JSON string
        # Uses native parsing and serializes the result to JSON
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param input [String] Input string to parse
        # @return [String] JSON string representing the result
        def parse_to_json(grammar_json, input)
          unless available?
            raise LoadError,
                  "Serialized mode requires native extension. " \
                  "Run `rake compile` to build the extension."
          end

          # Parse using native engine and convert result to JSON
          result = parse(grammar_json, input)
          result.to_json
        end

        # Parse and return direct Ruby objects via FFI
        # Uses ZeroCopy mode - Rust constructs Ruby objects directly via magnus FFI
        # This bypasses the u64 serialization step for maximum performance.
        #
        # Slice information is preserved: InputRef nodes from Rust are returned
        # directly as Parsanol::Slice objects (no intermediate hash conversion needed).
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param input [String] Input string to parse
        # @param type_map [Hash] Mapping of rule names to Ruby classes (not used in this mode)
        # @return [Object] Direct Ruby object (type depends on grammar)
        def parse_to_objects(grammar_json, input, _type_map = nil)
          unless available?
            raise LoadError,
                  "ZeroCopy mode requires native extension. " \
                  "Run `rake compile` to build the extension."
          end

          # Call Rust function that returns Slice objects directly
          # No need to convert - they are already Parsanol::Slice objects
          Parsanol::Native.parse_to_ruby_objects(grammar_json, input)
        end

        # Recursively convert slice hashes to Parsanol::Slice objects
        # Rust returns { "_slice" => true, "str" => "...", "offset" => N, "length" => N }
        # for InputRef nodes, which we convert to Slice objects preserving position info.
        #
        # @param obj [Object] The object to convert (may be Hash, Array, or leaf value)
        # @param input [String] The original input string (for Slice source reference)
        # @return [Object] The converted object with Slice objects in place of slice hashes
        def convert_slices(obj, input)
          case obj
          when Hash
            # Check if this is a slice marker from Rust
            if obj['_slice'] == true
              Parsanol::Slice.new(obj['offset'], obj['str'])
            else
              # Recursively convert hash values
              obj.transform_values { |v| convert_slices(v, input) }
            end
          when Array
            # Recursively convert array elements
            obj.map { |item| convert_slices(item, input) }
          else
            # Leaf values (strings, integers, etc.) are returned as-is
            obj
          end
        end

        # ===== Source Location Tracking =====

        # Parse with source location tracking
        # Returns both the AST and a hash of spans
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param input [String] Input string to parse
        # @return [Array<(Object, Hash)>] Tuple of [parsed_result, spans_hash]
        def parse_with_spans(grammar_json, input)
          unless available?
            raise LoadError,
                  "Source location tracking requires native extension. " \
                  "Run `rake compile` to build the extension."
          end

          _parse_with_spans(grammar_json, input)
        end

        # Get span for a specific node
        #
        # @param result [Object] Parse result from parse_with_spans
        # @param node_id [Integer] Node identifier
        # @return [Hash] Span information {start: {offset, line, column}, end: {...}}
        def get_span(result, node_id)
          raise LoadError, 'Source location tracking requires native extension.' unless available?

          _get_span(result, node_id)
        end

        # ===== Grammar Composition =====

        # Import another grammar with optional prefix
        #
        # @param builder_json [String] GrammarBuilder JSON
        # @param grammar_json [String] Grammar to import
        # @param prefix [String, nil] Optional prefix for imported rules
        # @return [String] Updated GrammarBuilder JSON
        def grammar_import(builder_json, grammar_json, prefix = nil)
          raise LoadError, 'Grammar composition requires native extension.' unless available?

          _grammar_import(builder_json, grammar_json, prefix)
        end

        # Get mutable reference to a rule
        #
        # @param builder_json [String] GrammarBuilder JSON
        # @param rule_name [String] Name of the rule to modify
        # @return [String] Updated GrammarBuilder JSON
        def grammar_rule_mut(builder_json, rule_name)
          raise LoadError, 'Grammar composition requires native extension.' unless available?

          _grammar_rule_mut(builder_json, rule_name)
        end

        # ===== Streaming Parser =====

        # Create a new streaming parser
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @return [Object] Streaming parser instance
        def streaming_parser_new(grammar_json)
          raise LoadError, 'Streaming parser requires native extension.' unless available?

          _streaming_parser_new(grammar_json)
        end

        # Add a chunk to the streaming parser
        #
        # @param parser [Object] Streaming parser instance
        # @param chunk [String] Input chunk to add
        # @return [Boolean] True if more chunks needed, false if ready
        def streaming_parser_add_chunk(parser, chunk)
          raise LoadError, 'Streaming parser requires native extension.' unless available?

          _streaming_parser_add_chunk(parser, chunk)
        end

        # Parse what we have so far
        #
        # @param parser [Object] Streaming parser instance
        # @return [Object, nil] Parsed result or nil if need more data
        def streaming_parser_parse_chunk(parser)
          raise LoadError, 'Streaming parser requires native extension.' unless available?

          _streaming_parser_parse_chunk(parser)
        end

        # ===== Incremental Parser =====

        # Create a new incremental parser
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param initial_input [String] Initial input string
        # @return [Object] Incremental parser instance
        def incremental_parser_new(grammar_json, initial_input)
          raise LoadError, 'Incremental parser requires native extension.' unless available?

          _incremental_parser_new(grammar_json, initial_input)
        end

        # Apply an edit to the incremental parser
        #
        # @param parser [Object] Incremental parser instance
        # @param start [Integer] Start position of edit
        # @param deleted [Integer] Number of characters deleted
        # @param inserted [String] Text to insert
        # @return [Object] Updated parser state
        def incremental_parser_apply_edit(parser, start, deleted, inserted = '')
          raise LoadError, 'Incremental parser requires native extension.' unless available?

          _incremental_parser_apply_edit(parser, start, deleted, inserted)
        end

        # Reparse with changes
        #
        # @param parser [Object] Incremental parser instance
        # @param new_input [String, nil] Optional new input (if not using apply_edit)
        # @return [Object] Parse result
        def incremental_parser_reparse(parser, new_input = nil)
          raise LoadError, 'Incremental parser requires native extension.' unless available?

          _incremental_parser_reparse(parser, new_input)
        end

        # ===== Streaming Builder =====

        # Parse with a streaming builder for maximum performance.
        # The builder receives callbacks as parsing progresses, eliminating
        # intermediate AST construction.
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param input [String] Input string to parse
        # @param builder [Object] Object including BuilderCallbacks module
        # @return [Object] Result of builder.finish
        def parse_with_builder(grammar_json, input, builder)
          unless available?
            raise LoadError,
                  "Streaming builder requires native extension. " \
                  "Run `rake compile` to build the extension."
          end

          _parse_with_builder(grammar_json, input, builder)
        end

        # ===== Parallel Parsing =====

        # Parse multiple inputs in parallel using rayon.
        # Provides linear speedup on multi-core systems.
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param inputs [Array<String>] Array of input strings to parse
        # @param num_threads [Integer, nil] Number of threads (nil = auto-detect)
        # @return [Array<Object>] Array of parse results in same order as inputs
        def parse_batch_parallel(grammar_json, inputs, num_threads: nil)
          unless available?
            raise LoadError,
                  "Parallel parsing requires native extension. " \
                  "Run `rake compile` to build the extension."
          end

          _parse_batch_parallel(grammar_json, inputs, num_threads)
        end

        # ===== Security / Limits =====

        # Parse with custom limits for untrusted input.
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param input [String] Input string to parse
        # @param max_input_size [Integer] Maximum input size in bytes (default: 100MB)
        # @param max_recursion_depth [Integer] Maximum recursion depth (default: 1000)
        # @return [Object] Parse result
        def parse_with_limits(grammar_json, input, max_input_size: 100 * 1024 * 1024, max_recursion_depth: 1000)
          unless available?
            raise LoadError,
                  "Security limits require native extension. " \
                  "Run `rake compile` to build the extension."
          end

          _parse_with_limits(grammar_json, input, max_input_size, max_recursion_depth)
        end

        # ===== Debug Tools =====

        # Parse with tracing enabled for debugging.
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @param input [String] Input string to parse
        # @return [Array<(Object, Array)>] Tuple of [parse_result, trace_events]
        def parse_with_trace(grammar_json, input)
          unless available?
            raise LoadError,
                  "Debug tracing requires native extension. " \
                  "Run `rake compile` to build the extension."
          end

          _parse_with_trace(grammar_json, input)
        end

        # Generate Mermaid diagram for a grammar.
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @return [String] Mermaid diagram source
        def grammar_to_mermaid(grammar_json)
          unless available?
            raise LoadError,
                  "Grammar visualization requires native extension. " \
                  "Run `rake compile` to build the extension."
          end

          _grammar_to_mermaid(grammar_json)
        end

        # Generate GraphViz DOT diagram for a grammar.
        #
        # @param grammar_json [String] JSON-serialized grammar
        # @return [String] GraphViz DOT source
        def grammar_to_dot(grammar_json)
          unless available?
            raise LoadError,
                  "Grammar visualization requires native extension. " \
                  "Run `rake compile` to build the extension."
          end

          _grammar_to_dot(grammar_json)
        end

        private

        def _incremental_parser_reparse(parser, new_input)
          raise NotImplementedError, 'Native extension method not available'
        end

        def _parse_with_builder(grammar_json, input, builder)
          # Call native Rust function directly - parse_with_builder is exposed
          # from the native extension as a Ruby function
          Parsanol::Native.parse_with_builder(grammar_json, input, builder)
        end

        def _parse_batch_parallel(grammar_json, inputs, num_threads)
          raise NotImplementedError, 'Native extension method not available'
        end

        def _parse_with_limits(grammar_json, input, max_input_size, max_recursion_depth)
          raise NotImplementedError, 'Native extension method not available'
        end

        def _parse_with_trace(grammar_json, input)
          raise NotImplementedError, 'Native extension method not available'
        end

        def _grammar_to_mermaid(grammar_json)
          raise NotImplementedError, 'Native extension method not available'
        end

        def _grammar_to_dot(grammar_json)
          raise NotImplementedError, 'Native extension method not available'
        end

        # Decode flat u64 array to Ruby AST
        # Tags:
        #   0x00 = nil
        #   0x01 = bool
        #   0x02 = int
        #   0x03 = float
        #   0x04 = string_ref (offset, length)
        #   0x05 = array_start
        #   0x06 = array_end
        #   0x07 = hash_start
        #   0x08 = hash_end
        #   0x09 = hash_key (tag, len, key_chunks..., value)
        def decode_flat(flat, input)
          stack = []
          i = 0

          while i < flat.length
            tag = flat[i]

            case tag
            when 0x00 # nil
              stack << nil
              i += 1
            when 0x01 # bool
              stack << (flat[i + 1] != 0)
              i += 2
            when 0x02 # int
              stack << flat[i + 1]
              i += 2
            when 0x03 # float
              # Decode IEEE 754 float from bits
              bits = flat[i + 1]
              float = [bits].pack('Q').unpack1('D')
              stack << float
              i += 2
            when 0x04 # string_ref (from input)
              offset = flat[i + 1]
              length = flat[i + 2]
              stack << input.byteslice(offset, length)
              i += 3
            when 0x0A # inline_string (interned string from arena)
              # Format: tag, len, u64 chunks of string bytes
              len = flat[i + 1]
              i += 2

              # Read string bytes from u64 chunks
              chunks = (len + 7) / 8
              bytes = []
              chunks.times do |j|
                chunk = flat[i + j]
                8.times do |k|
                  break if bytes.length >= len

                  bytes << ((chunk >> (k * 8)) & 0xff)
                end
              end
              i += chunks

              stack << bytes.pack('C*').force_encoding('UTF-8')
            when 0x05 # array_start
              stack << :array_marker
              i += 1
            when 0x06 # array_end
              items = []
              items.unshift(stack.pop) until stack.last == :array_marker
              stack.pop # Remove marker
              stack << items
              i += 1
            when 0x07 # hash_start
              stack << :hash_marker
              i += 1
            when 0x08 # hash_end
              pairs = []
              while stack.last != :hash_marker
                value = stack.pop
                key = stack.pop
                pairs.unshift([key, value])
              end
              stack.pop # Remove marker
              stack << pairs.to_h
              i += 1
            when 0x09 # hash_key
              # Format: tag, len, key_chunks..., then value
              len = flat[i + 1]
              i += 2 # Skip tag and len

              # Read key bytes from u64 chunks
              chunks = (len + 7) / 8
              key_bytes = []
              chunks.times do |j|
                chunk = flat[i + j]
                8.times do |k|
                  break if key_bytes.length >= len

                  key_bytes << ((chunk >> (k * 8)) & 0xff)
                end
              end
              i += chunks

              key = key_bytes.pack('C*').force_encoding('UTF-8')
              stack << key
            else
              raise "Unknown tag: #{tag} at index #{i}"
            end
          end

          stack.first
        end

        # Compute structural hash of a grammar atom
        # This returns the same hash for grammars with the same structure
        # regardless of whether they are different object instances
        def grammar_structure_hash(atom)
          structure = atom_structure(atom)
          Digest::MD5.hexdigest(structure.to_s)
        end

        # Recursively build structure representation for hashing
        def atom_structure(atom)
          case atom
          when ::Parsanol::Atoms::Str
            [:str, atom.str]
          when ::Parsanol::Atoms::Re
            [:re, atom.match]
          when ::Parsanol::Atoms::Sequence
            [:seq, atom.parslets.map { |p| atom_structure(p) }]
          when ::Parsanol::Atoms::Alternative
            [:alt, atom.alternatives.map { |p| atom_structure(p) }]
          when ::Parsanol::Atoms::Repetition
            [:rep, atom.min, atom.max, atom_structure(atom.parslet)]
          when ::Parsanol::Atoms::Named
            [:named, atom.name.to_s, atom_structure(atom.parslet)]
          when ::Parsanol::Atoms::Lookahead
            [:lookahead, atom.positive, atom_structure(atom.bound_parslet)]
          when ::Parsanol::Atoms::Entity
            # Entity is a lazy reference - use its name for hashing
            [:entity, atom.name.to_s]
          else
            [:unknown, atom.class.name]
          end
        end
      end
    end
  end
end
