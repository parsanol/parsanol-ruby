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

puts "=" * 60
puts "Parsanol Grammar Caching Benchmark"
puts "=" * 60

parser = SimpleParser.new

# Test input - simple list of values
test_input = "one, two, three, four, five, six, seven, eight, nine, ten"

# Warm-up run
puts "\nWarming up..."
10.times { parser.parse(test_input) }

# Benchmark: First parse (no cache)
puts "\n--- First Parse (no cache) ---"
first_time = Benchmark.realtime do
  parser.parse(test_input)
end
puts "First parse: #{(first_time * 1000).round(2)} ms"

# Benchmark: Cached parses
puts "\n--- Cached Parses (100 iterations) ---"
cached_times = []
100.times do
  time = Benchmark.realtime do
    parser.parse(test_input)
  end
  cached_times << time
end

avg_cached = cached_times.sum / cached_times.length
min_cached = cached_times.min
max_cached = cached_times.max

puts "Average cached parse: #{(avg_cached * 1000).round(2)} ms"
puts "Min cached parse: #{(min_cached * 1000).round(2)} ms"
puts "Max cached parse: #{(max_cached * 1000).round(2)} ms"

# Calculate improvement
improvement = ((first_time - avg_cached) / first_time * 100).round(1)
puts "\nFirst-to-cached improvement: #{improvement}% faster"

# Larger input test
puts "\n--- Larger Input Test ---"
# Use pure word input to avoid number/word parsing issues
large_input = (1..100).map { |i| "word" }.join(", ")

# Warm up
3.times { parser.parse(large_input) }

large_times = 20.times.map do
  Benchmark.realtime { parser.parse(large_input) }
end

avg_large = large_times.sum / large_times.length
puts "Input size: #{large_input.length} chars"
puts "Average parse: #{(avg_large * 1000).round(2)} ms"

puts "\n" + "=" * 60
puts "Benchmark complete"
puts "=" * 60
