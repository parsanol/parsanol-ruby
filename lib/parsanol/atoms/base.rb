# frozen_string_literal: true

# Base class for all parser atoms. Handles parsing orchestration,
# memoization, error handling, and result processing.
#
# Concrete atoms must implement #try(source, context, consume_all).
#
# @abstract Implement #try to create custom parser atoms
module Parsanol
  module Atoms
    class Base
      include Parsanol::Atoms::Precedence
      include Parsanol::Atoms::DSL
      include Parsanol::Atoms::CanFlatten
      include Parsanol::FirstSet

      # Label used for error messages (optional)
      attr_accessor :label

      # Error message for unconsumed input
      UNCONSUMED_INPUT_MSG = "Don't know what to do with "

      # Primary parsing interface. Takes a string or Source and returns
      # the parsed tree, or raises ParseFailed on error.
      #
      # @param source [String, Parsanol::Source] input to parse
      # @param options [Hash] parsing options
      # @option options [Parsanol::ErrorReporter] :reporter error collector
      # @option options [Boolean] :prefix allow partial parse (default: false)
      # @return [Object] the parsed result
      # @raise [Parsanol::ParseFailed] on parse failure
      def parse(source, options = {})
        input = normalize_input(source)
        must_consume_all = !options[:prefix]

        # Initial parse attempt (no error collection)
        success, value = run_with_context(input, nil, must_consume_all)
        return finalize_result(value) if success

        # Reparse with error reporting for diagnostics
        report_detailed_error(input, must_consume_all, options[:reporter],
                              value)
      end

      # Creates a new parsing context and executes the atom.
      #
      # @param input [Parsanol::Source] the source
      # @param reporter [Object, nil] error reporter
      # @param consume_all [Boolean] require complete consumption
      # @return [Array(Boolean, Object)] outcome tuple
      def run_with_context(input, reporter, consume_all)
        parser_class = detect_parser_class
        context = Parsanol::Atoms::Context.new(reporter,
                                               parser_class: parser_class)
        apply(input, context, consume_all)
      end

      # Core execution method. Manages position, caching, and error handling.
      #
      # @param input [Parsanol::Source] source to parse
      # @param context [Parsanol::Atoms::Context] parsing state
      # @param consume_all [Boolean] consume entire input
      # @return [Array(Boolean, Object)] outcome pair
      def apply(input, context, consume_all = false)
        position_before = input.bytepos
        outcome = context.try_with_cache(self, input, consume_all)
        succeeded = outcome.first

        return handle_failure(input, position_before, outcome) unless succeeded

        context.succ(input)

        # Verify full consumption when required
        if consume_all && input.chars_left.positive?
          return unconsumed_error(input, context,
                                  position_before)
        end

        outcome
      end

      # Abstract matching method - override in subclasses.
      #
      # @param input [Parsanol::Source] source
      # @param context [Parsanol::Atoms::Context] context
      # @param consume_all [Boolean] consume all flag
      # @return [Array(Boolean, Object)] parse result
      # @raise [NotImplementedError] if not overridden
      def try(input, context, consume_all)
        raise NotImplementedError,
              "Atom must implement #try(source, context, consume_all)"
      end

      # Whether packrat caching benefits this atom.
      # Override to disable caching for simple atoms.
      #
      # @return [Boolean]
      def cached?
        true
      end

      # Whether this atom produces flat results.
      # When true, flattening can be skipped.
      #
      # @return [Boolean]
      def flat?
        false
      end

      # DSL for setting precedence level (for pretty-printing).
      #
      # @param level [Integer] precedence value
      def self.precedence(level)
        define_method(:precedence) { level }
      end
      precedence ATOM

      # String representation with precedence-aware parenthesization.
      #
      # @param outer [Integer] caller's precedence
      # @return [String]
      def to_s(outer = TOP)
        text = label || to_s_inner(precedence)
        outer < precedence ? "(#{text})" : text
      end

      def inspect
        to_s(TOP)
      end

      protected

      # Pre-allocated constant result tuples
      NIL_OK = [true, nil].freeze
      EMPTY_ARR = [].freeze
      REP_TAG = [:repetition].freeze
      REP_OK = [true, REP_TAG].freeze
      SEQ_TAG = [:sequence].freeze
      SEQ_OK = [true, SEQ_TAG].freeze
      EMPTY_MAP = {}.freeze
      MAP_OK = [true, EMPTY_MAP].freeze
      CAP_TAG = [:capture].freeze
      CAP_OK = [true, CAP_TAG].freeze

      # Creates a success tuple.
      #
      # @param data [Object] the value
      # @return [Array(true, Object)]
      def ok(data)
        return NIL_OK if data.nil?
        return [true, EMPTY_ARR] if data.equal?(EMPTY_ARR)
        return MAP_OK if data.equal?(EMPTY_MAP)
        return REP_OK if data.equal?(REP_TAG)
        return SEQ_OK if data.equal?(SEQ_TAG)
        return CAP_OK if data.equal?(CAP_TAG)

        [true, data]
      end

      # Alias for ok (legacy compatibility)
      alias succ ok

      private

      # Converts raw input to Source if needed.
      def normalize_input(source)
        source.respond_to?(:line_and_column) ? source : Parsanol::Source.new(source)
      end

      # Detects if we're in a Parser context.
      def detect_parser_class
        is_a?(Parsanol::Parser) ? self.class : nil
      end

      # Handles parse failure by restoring position.
      def handle_failure(input, saved_pos, outcome)
        input.bytepos = saved_pos
        outcome
      end

      # Creates error for unconsumed input.
      def unconsumed_error(input, context, saved_pos)
        excess_pos = input.bytepos
        preview = input.consume(10)
        input.bytepos = saved_pos
        context.err_at(self, input,
                       UNCONSUMED_INPUT_MSG + preview.to_s.inspect, excess_pos)
      end

      # Reports detailed error by reparsing with reporter.
      def report_detailed_error(input, consume_all, reporter, _initial_error)
        input.bytepos = 0
        error_reporter = reporter || Parsanol::ErrorReporter::Tree.new
        success, cause = run_with_context(input, error_reporter, consume_all)

        # Second parse should also fail
        raise "Invariant violation: parse succeeded during error reporting" if success

        cause.raise
      end

      # Finalizes result by flattening.
      def finalize_result(value)
        flatten(value)
      end
    end
  end
end
