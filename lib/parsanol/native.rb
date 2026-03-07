# frozen_string_literal: true

require 'json'
require 'digest'

# Entry point for native parsing functionality
# Requires the individual components
require 'parsanol/native/types'
require 'parsanol/native/parser'
require 'parsanol/native/transformer'
require 'parsanol/native/serializer'
require 'parsanol/native/dynamic'
require 'parsanol/native/dynamic'

module Parsanol
  module Native
    VERSION = '0.1.0'

    class << self
      # Delegate to Parser module
      def available?
        Parser.available?
      end

      def parse(grammar_json, input)
        Parser.parse(grammar_json, input)
      end

      def parse_with_grammar(root_atom, input)
        Parser.parse_with_grammar(root_atom, input)
      end

      def parse_parslet_compatible(root_atom, input)
        Parser.parse_parslet_compatible(root_atom, input)
      end

      def parse_batch_inputs(root_atom, inputs)
        Parser.parse_batch_inputs(root_atom, inputs)
      end

      def parse_batch_with_transform(root_atom, inputs)
        Parser.parse_batch_with_transform(root_atom, inputs)
      end

      def parse_raw(root_atom, input)
        Parser.parse_raw(root_atom, input)
      end

      def serialize_grammar(root_atom)
        Parser.serialize_grammar(root_atom)
      end

      def clear_cache
        Parser.clear_cache
      end

      def cache_stats
        Parser.cache_stats
      end

      # Serialized Mode (JSON Output)
      def parse_to_json(grammar_json, input)
        Parser.parse_to_json(grammar_json, input)
      end

      # ZeroCopy Mode (Direct Ruby Objects)
      def parse_to_objects(grammar_json, input, type_map = nil)
        Parser.parse_to_objects(grammar_json, input, type_map)
      end

      def convert_slices(obj, input)
        Parser.convert_slices(obj, input)
      end

      # Source Location Tracking
      def parse_with_spans(grammar_json, input)
        Parser.parse_with_spans(grammar_json, input)
      end

      def get_span(result, node_id)
        Parser.get_span(result, node_id)
      end

      # Grammar Composition
      def grammar_import(builder_json, grammar_json, prefix = nil)
        Parser.grammar_import(builder_json, grammar_json, prefix)
      end

      def grammar_rule_mut(builder_json, rule_name)
        Parser.grammar_rule_mut(builder_json, rule_name)
      end

      # Streaming Parser
      def streaming_parser_new(grammar_json)
        Parser.streaming_parser_new(grammar_json)
      end

      def streaming_parser_add_chunk(parser, chunk)
        Parser.streaming_parser_add_chunk(parser, chunk)
      end

      def streaming_parser_parse_chunk(parser)
        Parser.streaming_parser_parse_chunk(parser)
      end

      # Incremental Parser
      def incremental_parser_new(grammar_json, initial_input)
        Parser.incremental_parser_new(grammar_json, initial_input)
      end

      def incremental_parser_apply_edit(parser, start, deleted, inserted = '')
        Parser.incremental_parser_apply_edit(parser, start, deleted, inserted)
      end

      def incremental_parser_reparse(parser, new_input = nil)
        Parser.incremental_parser_reparse(parser, new_input)
      end

      # Streaming Builder - uses native parse_with_builder directly (exposed from Rust)
      # The native function is exposed directly on Parsanol::Native module

      # Alias for parse_with_builder (same functionality)
      def parse_with_callback(grammar_json, input, callback)
        parse_with_builder(grammar_json, input, callback)
      end

      # Parallel Parsing - uses native _parse_batch_parallel
      def parse_batch_parallel(grammar_json, inputs, num_threads: nil)
        _parse_batch_parallel(grammar_json, inputs, num_threads || 0)
      end

      # Security / Limits - uses native _parse_with_limits
      def parse_with_limits(grammar_json, input, max_input_size: 100 * 1024 * 1024, max_recursion_depth: 1000)
        _parse_with_limits(grammar_json, input, max_input_size, max_recursion_depth)
      end

      # Debug Tools
      def parse_with_trace(grammar_json, input)
        Parser.parse_with_trace(grammar_json, input)
      end

      def grammar_to_mermaid(grammar_json)
        Parser.grammar_to_mermaid(grammar_json)
      end

      def grammar_to_dot(grammar_json)
        Parser.grammar_to_dot(grammar_json)
      end

      # Legacy internal methods (for backward compatibility)
      def _parse_with_spans(grammar_json, input)
        Parser.send(:_parse_with_spans, grammar_json, input)
      end

      def _get_span(result, node_id)
        Parser.send(:_get_span, result, node_id)
      end

      def _grammar_import(builder_json, grammar_json, prefix)
        Parser.send(:_grammar_import, builder_json, grammar_json, prefix)
      end

      def _grammar_rule_mut(builder_json, rule_name)
        Parser.send(:_grammar_rule_mut, builder_json, rule_name)
      end

      def _streaming_parser_new(grammar_json)
        Parser.send(:_streaming_parser_new, grammar_json)
      end

      def _streaming_parser_add_chunk(parser, chunk)
        Parser.send(:_streaming_parser_add_chunk, parser, chunk)
      end

      def _streaming_parser_parse_chunk(parser)
        Parser.send(:_streaming_parser_parse_chunk, parser)
      end

      def _incremental_parser_new(grammar_json, initial_input)
        Parser.send(:_incremental_parser_new, grammar_json, initial_input)
      end

      def _incremental_parser_apply_edit(parser, start, deleted, inserted)
        Parser.send(:_incremental_parser_apply_edit, parser, start, deleted, inserted)
      end

      def _incremental_parser_reparse(parser, new_input)
        Parser.send(:_incremental_parser_reparse, parser, new_input)
      end

      def _parse_batch_parallel(grammar_json, inputs, num_threads)
        Parser.send(:_parse_batch_parallel, grammar_json, inputs, num_threads)
      end

      def _parse_with_limits(grammar_json, input, max_input_size, max_recursion_depth)
        Parser.send(:_parse_with_limits, grammar_json, input, max_input_size, max_recursion_depth)
      end

      def _parse_with_trace(grammar_json, input)
        Parser.send(:_parse_with_trace, grammar_json, input)
      end

      def _grammar_to_mermaid(grammar_json)
        Parser.send(:_grammar_to_mermaid, grammar_json)
      end

      def _grammar_to_dot(grammar_json)
        Parser.send(:_grammar_to_dot, grammar_json)
      end
    end
  end
end

# Attempt to load native extension
# rb_sys puts native extensions in version-specific directories (e.g., parsanol/3.2/parsanol_native)
begin
  # Try version-specific path first (for precompiled gems)
  ruby_version = RUBY_VERSION.split('.').take(2).join('.')
  require "parsanol/#{ruby_version}/parsanol_native"
rescue LoadError
  begin
    # Fall back to generic path (for locally compiled extensions)
    require 'parsanol/parsanol_native'
  rescue LoadError
    # Native extension not built yet
  end
end
