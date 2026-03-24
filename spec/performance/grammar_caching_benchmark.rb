# frozen_string_literal: true

require "benchmark"
require "parslet"

# Test the grammar caching performance using the native parser
# This benchmark compares parse times for repeated parsing with the same grammar

class SimpleParser < Parsanol::Parser
  rule(:comma) { str(",") >> str(" ").maybe }
  rule(:word) { match(/[a-z]/).repeat(1) }
  rule(:alnum) { match(/[a-z0-9]/).repeat(1) }

  rule(:value) { (word | alnum).as(:v) }
  rule(:list) { value >> (comma >> value).repeat }

  root(:list)
end

parser = SimpleParser.new

# Test input - simple list of values
test_input = "one, two, three, four, five, six, seven, eight, nine, ten"

# Warm-up run

10.times { parser.parse(test_input) }

# Benchmark: First parse (no cache)

first_time = Benchmark.realtime do
  parser.parse(test_input)
end

# Benchmark: Cached parses

cached_times = []
100.times do
  time = Benchmark.realtime do
    parser.parse(test_input)
  end
  cached_times << time
end

avg_cached = cached_times.sum / cached_times.length
cached_times.min
cached_times.max

# Calculate improvement
((first_time - avg_cached) / first_time * 100).round(1)

# Larger input test

# Use pure word input to avoid number/word parsing issues
large_input = (1..100).map { |_i| "word" }.join(", ")

# Warm up
3.times { parser.parse(large_input) }

large_times = Array.new(20) do
  Benchmark.realtime { parser.parse(large_input) }
end

large_times.sum / large_times.length
