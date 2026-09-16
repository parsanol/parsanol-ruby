# frozen_string_literal: true

require "json"
require "digest"

require "parsanol/native/types"
require "parsanol/native/parser"
require "parsanol/native/serializer"
require "parsanol/native/batch_decoder"

module Parsanol
  module Native
    # Raised when a grammar uses atoms the Rust backend cannot express.
    # Failing at registration (TODO.perf/8 item 4) instead of planting a
    # never-matching placeholder that explodes mid-parse.
    class UnsupportedGrammar < ArgumentError; end

    # ffi-gem cdylib tier: lazy — only loaded when the MRI extension is absent.
    autoload :Ffi, "parsanol/native/ffi"
    # Dynamic-atom callbacks: autoloaded so the serializer's reference
    # never raises NameError into the silent :ruby fallback (issue #38).
    autoload :Dynamic, "parsanol/native/dynamic"
    class << self
      # Check if native extension is available
      def available?
        Parser.available?
      end

      # Parse input with a Ruby grammar, returning clean AST with lazy line/column.
      #
      # Uses batch FFI format for maximum performance (3-5x faster than object-by-object).
      # The Rust-side transformation (to_parslet_compatible) produces Parslet-compatible
      # output that can be consumed directly by Builder.build without additional
      # Ruby-side transformation.
      #
      # @param grammar [Parsanol::Atoms::Base] Ruby grammar definition
      # @param input [String] Input string to parse
      # @return [Hash, Array, Parsanol::Slice] Transformed AST
      #
      # @example Simple parsing
      #   result = Parsanol::Native.parse(str('hello').as(:greeting), 'hello')
      #   # => {greeting: "hello"@0}
      #
      # @example With lazy line/column
      #   result = Parsanol::Native.parse(str('hello').as(:greeting), "hello\nworld")
      #   result[:greeting].line_and_column  # => [1, 1]
      #
      def parse(grammar, input)
        raise LoadError, "Native parser not available" unless available?

        # ffi-gem tier (JRuby/TruffleRuby/no-binary MRI): same contract,
        # batch-decoded results, single reporter-pass error fallback.
        return Ffi.parse(grammar, input) unless Parser.extension_loaded?

        # Both sub-methods return the final decoded tree; on native failure
        # they fall back to the pure-Ruby parser, whose result is already
        # final and must not be transformed again.
        if grammar.is_a?(String)
          parse_json_grammar(grammar, input)
        else
          parse_atom_grammar(grammar, input)
        end
      end

      # Memory-bounded parsing without packrat cache.
      #
      # This creates a fresh arena and empty cache per call, bounding memory
      # to AST size rather than input × atoms. Use for large files.
      #
      # @param grammar [Parsanol::Atoms::Base] Ruby grammar definition
      # @param input [String] Input string to parse
      # @return [Hash, Array, Parsanol::Slice] Transformed AST
      def parse_fresh(grammar, input)
        raise LoadError, "Native parser not available" unless available?

        grammar_json = if grammar.is_a?(String)
                         grammar
                       else
                         Parser.serialize_grammar(grammar)
                       end

        # Decode here, not around the fallback: raise_native_parse_error
        # returns the Ruby parser's already-final tree on success.
        begin
          BatchDecoder.decode_and_flatten(_parse_fresh_raw(grammar_json, input),
                                          input, Parsanol::Slice)
        rescue RuntimeError => e
          raise_native_parse_error(e, grammar, input)
        end
      end

      # Parse and return RAW AST without transformation.
      #
      # This returns the raw Parslet intermediate format before any transformation.
      # Use this only if you need the raw AST for custom processing.
      #
      # For most use cases (including Expressir), use parse() instead which
      # returns properly transformed AST.
      #
      # @param grammar [Parsanol::Atoms::Base] Ruby grammar definition
      # @param input [String] Input string to parse
      # @return [Hash, Array] Raw untransformed AST
      #
      # @example Raw parsing
      #   result = Parsanol::Native.parse_raw(str('hello').as(:greeting), 'hello')
      #   # => {:syntax => [{:spaces => ...}, {:greeting => "hello"@0}, {:spaces => ...}]}
      #
      def parse_raw(grammar, input)
        raise LoadError, "Native parser not available" unless available?

        # Handle both grammar atoms and pre-serialized JSON strings
        grammar_json = if grammar.is_a?(String)
                         grammar
                       else
                         Parser.serialize_grammar(grammar)
                       end

        # Use batch_raw format for raw AST (no transformation)
        slice_class = Parsanol::Slice
        batch_data = _parse_batch_raw(grammar_json, input)

        # Decode without transformation - raw AST format
        BatchDecoder.decode(batch_data, input, slice_class)
      end

      # Fast batch parsing - uses u64 array format to minimize FFI overhead.
      #
      # This is 3-5x faster than regular parse() for large grammars.
      # The batch format passes a flat u64 array across FFI, then decodes
      # in pure Ruby, avoiding expensive per-node FFI calls.
      #
      # Returns RAW AST without transformation. For Expressir use case,
      # use parse() instead which returns properly transformed AST.
      #
      # @param grammar_json [String] Pre-serialized grammar JSON
      # @param input [String] Input string to parse
      # @param slice_class [Class] The Slice class to use for string refs
      # @return [Hash, Array, Slice] Raw AST (not transformed)
      def parse_batch(grammar_json, input, slice_class)
        raise LoadError, "Native parser not available" unless available?

        # Call native extension's _parse_batch_raw method (named with _raw suffix
        # to avoid conflict with this Ruby wrapper method)
        batch_data = _parse_batch_raw(grammar_json, input)
        BatchDecoder.decode(batch_data, input, slice_class)
      end

      # Serialize a Ruby grammar to JSON (cached).
      #
      # @param root_atom [Parsanol::Atoms::Base] Root atom of the grammar
      # @return [String] JSON string
      def serialize_grammar(root_atom)
        Parser.serialize_grammar(root_atom)
      end

      # Clear grammar caches (call if grammar changes)
      def clear_cache
        Parser.clear_cache
        clear_grammar_cache if available?
      end

      # Clear the Rust grammar cache to free memory.
      #
      # This is useful for batch processing scenarios where you want to
      # limit memory usage by clearing unused grammars.
      #
      # @return [nil]
      def clear_grammar_cache
        raise LoadError, "Native parser not available" unless available?

        _clear_grammar_cache
      end

      # Get the current number of cached grammars in Rust.
      #
      # @return [Integer] Number of cached grammars
      def grammar_cache_size
        raise LoadError, "Native parser not available" unless available?

        _grammar_cache_size
      end

      # Get the grammar cache capacity.
      #
      # @return [Integer] Maximum cache capacity
      def grammar_cache_capacity
        raise LoadError, "Native parser not available" unless available?

        _grammar_cache_capacity
      end

      # Get cache statistics
      def cache_stats
        stats = Parser.cache_stats
        if available?
          stats[:rust_grammar_cache_size] = grammar_cache_size
          stats[:rust_grammar_cache_capacity] = grammar_cache_capacity
        end
        stats
      end

      # Translates a native backend failure into the Parsanol error protocol.
      #
      # When the grammar atom is at hand, reparses through the pure Ruby
      # backend: a Ruby failure raises Parsanol::ParseFailed with the full
      # cause-tree diagnostics, and a Ruby success recovers grammars the
      # native serializer cannot express (e.g. custom atoms). For
      # pre-serialized JSON grammars the native message is wrapped in a
      # Parsanol::ParseFailed directly.
      NATIVE_POS_MARKER = /\n@@parsanol_pos:(\d+)\z/

      def raise_native_parse_error(error, grammar, input)
        # Native diagnostics: the Rust tracker reports the deepest
        # failure position and the terminals expected there. Build the
        # cause from that directly — the failure path never needs a
        # reporter reparse. The single interpreter pass below stays only
        # to recover inputs from grammars native cannot express.
        if grammar.respond_to?(:parse) && (m = error.message.match(NATIVE_POS_MARKER))
          source = Parsanol::Source.new(input)
          success, value = grammar.run_with_context(source, nil, true)
          return grammar.finalize_result(value) if success

          pos = m[1].to_i
          msg = error.message.sub(NATIVE_POS_MARKER, "")
          cause = Parsanol::Cause.new(msg, source, pos)
          raise Parsanol::ParseFailed.new(cause.to_s, cause)
        end

        if grammar.respond_to?(:parse)
          # No native diagnostics (e.g. incomplete-input errors): one
          # interpreter pass with the reporter attached — a success
          # recovers the tree, a failure raises the cause tree.
          reporter = Parsanol::ErrorReporter::Tree.new
          source = Parsanol::Source.new(input)
          success, value = grammar.run_with_context(source, reporter, true)
          return grammar.finalize_result(value) if success

          value.raise
        end

        source = Parsanol::Source.new(input)
        cause = Parsanol::Cause.new(error.message, source, source.bytepos)
        raise Parsanol::ParseFailed.new(cause.to_s, cause)
      end

      # Pre-serialized JSON grammar path (library authors with cached JSON).
      def parse_json_grammar(grammar_json, input)
        BatchDecoder.decode_and_flatten(_parse_raw(grammar_json, input),
                                        input, Parsanol::Slice)
      rescue RuntimeError => e
        raise_native_parse_error(e, grammar_json, input)
      end

      # Prefix-mode parse (partial match allowed): the grammar registers
      # by handle exactly like #parse; the Rust side returns
      # [value, end_pos] with trailing input unconsumed.
      def parse_prefix(grammar, input)
        handle = Parser.grammar_handle(grammar)

        begin
          value, end_pos = _parse_handle_prefix(handle, input)
          [value, end_pos]
        rescue ArgumentError
          Parser.invalidate_handle(handle)
          _parse_handle_prefix(Parser.grammar_handle(grammar), input)
        end
      end

      # Grammar-atom path: registers once and parses by Rust-side handle,
      # so steady-state calls marshal no JSON and copy no input string.
      def parse_atom_grammar(grammar, input)
        handle = Parser.grammar_handle(grammar)

        begin
          BatchDecoder.decode_and_flatten(_parse_handle(handle, input),
                                          input, Parsanol::Slice)
        rescue ArgumentError
          # Handle dropped Rust-side (e.g. cache cleared): re-register once.
          Parser.invalidate_handle(handle)
          begin
            BatchDecoder.decode_and_flatten(
              _parse_handle(Parser.grammar_handle(grammar), input),
              input, Parsanol::Slice
            )
          rescue RuntimeError => e
            raise_native_parse_error(e, grammar, input)
          end
        rescue RuntimeError => e
          raise_native_parse_error(e, grammar, input)
        end
      end
    end
  end
end

# Attempt to load native extension
begin
  ruby_version = RUBY_VERSION.split(".").take(2).join(".")
  require "parsanol/#{ruby_version}/parsanol_native"
rescue LoadError
  begin
    require "parsanol/parsanol_native"
  rescue LoadError
    # Native extension not built yet
  end
end
