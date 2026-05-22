# frozen_string_literal: true

# Reviewer probe for the parser-class adaptive cache threshold change.
#
# It compares the old unnamed parser fallback threshold of 1000 with the current
# parser-class default from Parsanol::Atoms::Context on a recursive grammar.
#
# Usage:
#   ruby benchmark/cache_threshold_recursive.rb
#   ITERATIONS=1000 ruby benchmark/cache_threshold_recursive.rb

require "benchmark"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "parsanol"

class RecursiveCacheThresholdParser < Parsanol::Parser
  rule(:digit) { match("[0-9]") }
  rule(:number) { digit.repeat(1).as(:number) }
  rule(:operator) { str("+") | str("-") | str("*") | str("/") }

  rule(:grouped) do
    str("(") >> expression.as(:expression) >> str(")")
  end

  rule(:binary) do
    str("(") >>
      expression.as(:left) >>
      operator.as(:operator) >>
      expression.as(:right) >>
      str(")")
  end

  rule(:expression) do
    grouped | binary | number
  end

  root(:expression)
end

ITERATIONS = Integer(ENV.fetch("ITERATIONS", "200"))
WARMUP = Integer(ENV.fetch("WARMUP", "20"))
INPUT = "((((1+2)+(3+4))+((5+6)+(7+8)))+(((9+10)+(11+12))+((13+14)+(15+16))))"
OLD_PARSER_FALLBACK_THRESHOLD = 1000

def parse_with_context(parser, threshold: nil)
  source = Parsanol::Source.new(INPUT)
  context_options = { parser_class: parser.class }
  context_options[:adaptive_cache_threshold] = threshold unless threshold.nil?
  context = Parsanol::Atoms::Context.new(nil, **context_options)

  success, value = parser.apply(source, context, true)
  raise "parse failed: #{value.inspect}" unless success
end

parser = RecursiveCacheThresholdParser.new

{
  "old parser fallback (1000)" => OLD_PARSER_FALLBACK_THRESHOLD,
  "current parser default" => nil,
}.each_value do |threshold|
  WARMUP.times { parse_with_context(parser, threshold: threshold) }
end

puts "Recursive parser cache threshold benchmark"
puts "input bytes: #{INPUT.bytesize}"
puts "iterations: #{ITERATIONS}"
puts

results = {}

{
  "old parser fallback (1000)" => OLD_PARSER_FALLBACK_THRESHOLD,
  "current parser default" => nil,
}.each do |label, threshold|
  total = Benchmark.realtime do
    ITERATIONS.times { parse_with_context(parser, threshold: threshold) }
  end

  average_ms = (total / ITERATIONS) * 1000
  results[label] = average_ms
  puts format("%-31s %8.3fms/parse", label, average_ms)
end

old_average = results.fetch("old parser fallback (1000)")
new_average = results.fetch("current parser default")
change = ((old_average - new_average) / old_average) * 100

puts
puts format("current default: %.1f%% %s", change.abs, change.negative? ? "slower" : "faster")
