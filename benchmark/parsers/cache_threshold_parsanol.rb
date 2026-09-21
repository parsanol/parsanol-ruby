# frozen_string_literal: true

# Synthetic recursive grammar for comparing adaptive cache thresholds
# Used only by the cache_threshold input type in run_all.rb

require "parsanol"

class CacheThresholdParsanolParser < Parsanol::Parser
  # Synthetic grammar with several recursive paths back into expression.
  # Used to compare parser-class cache thresholds on retry-heavy parses.
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }
  rule(:digit) { match("[0-9]") }
  rule(:number) { digit.repeat(1).as(:number) }
  rule(:identifier) { match("[a-zA-Z]") >> match("[a-zA-Z0-9]").repeat }
  rule(:operator) { str("+") | str("-") | str("*") | str("/") }
  rule(:separator) { str(",") >> space? }
  rule(:expression_stop) { str(",") | str(")") | str("]") }

  rule(:entry) { expression.as(:entry) }

  rule(:tuple) do
    str("(").as(:open_tuple) >> space? >>
      entry.as(:entries) >> (separator >> entry.as(:entries)).repeat >>
      space? >> str(")")
  end

  rule(:collection) do
    str("[").as(:collection_left) >> space? >>
      tuple.as(:tuple) >> (separator >> tuple.as(:tuple)).repeat >>
      space? >> str("]").as(:collection_right)
  end

  rule(:grouped_value) do
    str("(") >> expression.as(:expression) >> str(")")
  end

  rule(:primary) do
    grouped_value.as(:grouped_value) |
      number.as(:number) |
      identifier.as(:symbol)
  end

  rule(:decorated_value) do
    primary.as(:base_value) >> space? >>
      (str("_").as(:subscript) | str("^").as(:superscript)) >> space? >>
      primary.as(:decoration_value)
  end

  rule(:ratio) do
    primary.as(:ratio_left) >> space? >> str("/").as(:ratio) >> space? >>
      item.as(:ratio_right)
  end

  rule(:call) do
    identifier.as(:call_name) >> space? >> primary.as(:call_arg).maybe
  end

  rule(:item) do
    collection.as(:collection) |
      ratio.as(:ratio) |
      decorated_value.as(:decorated_value) |
      call.as(:call) |
      primary.as(:primary)
  end

  rule(:expression_tail) do
    expression_stop.absent? >>
      ((operator.as(:operator) >> space? >> expression.as(:right)) |
        expression.as(:expression))
  end

  rule(:expression) do
    item.as(:item) >> (space? >> expression_tail).maybe
  end

  rule(:document) do
    space? >> expression.as(:expression) >>
      (space >> expression.as(:expression)).repeat >> space?
  end

  root :document
end

module CacheThresholdParsanolBenchmark
  # The pre-parser-default threshold: atom-level contexts only memoize past
  # this input size (kept in sync with the lib constant).
  CONSERVATIVE_CACHE_THRESHOLD = Parsanol::Atoms::Context::DEFAULT_THRESHOLD

  module_function

  def default_threshold_parser
    parser = CacheThresholdParsanolParser.new
    ->(input) { parse_with_context(parser, input) }
  end

  def conservative_threshold_parser
    parser = CacheThresholdParsanolParser.new
    ->(input) { parse_with_context(parser, input, CONSERVATIVE_CACHE_THRESHOLD) }
  end

  def parse_with_context(parser, input, threshold = nil)
    source = Parsanol::Source.new(input)
    context_options = { parser_class: parser.class }
    context_options[:adaptive_cache_threshold] = threshold unless threshold.nil?
    context = Parsanol::Atoms::Context.new(nil, **context_options)

    success, value = parser.apply(source, context, true)
    raise "parse failed: #{value.inspect}" unless success

    # Mirror Base#parse's success path so the measured cost approximates real
    # parse() throughput rather than the raw parse loop alone.
    parser.flatten(value)
  end
end
