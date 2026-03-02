# frozen_string_literal: true

require "benchmark"
require "parslet"
require "parslet/native"

puts "=" * 60
puts "Parsanol Batch Parsing Benchmark"
puts "=" * 60

# First ensure native extension is loaded
unless Parsanol::Native.available?
  puts "ERROR: Native extension not available. Run 'rake compile' first."
  exit 1
end

class SimpleParser < Parsanol::Parser
  rule(:comma) { str(",") >> str(" ").maybe }
  rule(:word) { match(/[a-z]/).repeat(1) }
  rule(:alnum) { match(/[a-z0-9]/).repeat(1) }

  rule(:value) { (word | alnum).as(:v) }
  rule(:list) { value >> (comma >> value).repeat }

  root(:list)
end

parser = SimpleParser.new

# Create test inputs
inputs = (1..50).map { |i| "item#{i}, item#{i+1}, item#{i+2}" }

puts "\nTest: 50 inputs, 10 items each"
puts "Input count: #{inputs.length}"
puts "Total chars: #{inputs.sum(&:length)}"

# ============================================================================
# Test 1: Individual parsing (current approach)
# ============================================================================
puts "\n" + "-" * 60
puts "Test 1: Individual parsing (parse_parslet_compatible)"
puts "-" * 60

Parsanol::Native.clear_cache

individual_times = []
inputs.each do |input|
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  result = Parsanol::Native.parse_parslet_compatible(parser, input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start
  individual_times << elapsed
end

puts "Total time: #{individual_times.sum.round(0)} μs"
puts "Average per parse: #{(individual_times.sum / individual_times.length).round(2)} μs"
puts "Cache: #{Parsanol::Native.cache_stats}"

# ============================================================================
# Test 2: Batch parsing with transform
# ============================================================================
puts "\n" + "-" * 60
puts "Test 2: Batch parsing with transform (parse_batch_with_transform)"
puts "-" * 60

Parsanol::Native.clear_cache

start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
results = Parsanol::Native.parse_batch_with_transform(parser, inputs)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start

puts "Total time: #{elapsed.round(0)} μs"
puts "Average per parse: #{(elapsed / inputs.length).round(2)} μs"
puts "Results count: #{results.length}"
puts "Cache: #{Parsanol::Native.cache_stats}"

# ============================================================================
# Test 3: Raw parsing (no transform)
# ============================================================================
puts "\n" + "-" * 60
puts "Test 3: Raw parsing (parse_raw - no transformation)"
puts "-" * 60

Parsanol::Native.clear_cache

start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
results = Parsanol::Native.parse_batch(parser, inputs)
elapsed_raw = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start

puts "Total time: #{elapsed_raw.round(0)} μs"
puts "Average per parse: #{(elapsed_raw / inputs.length).round(2)} μs"
puts "Results count: #{results.length}"

# ============================================================================
# Comparison
# ============================================================================
puts "\n" + "=" * 60
puts "Comparison"
puts "=" * 60

total_individual = individual_times.sum
speedup_with_transform = (total_individual / elapsed).round(2)
speedup_raw = (total_individual / elapsed_raw).round(2)

puts "\nIndividual: #{total_individual.round(0)} μs"
puts "Batch + transform: #{elapsed.round(0)} μs"
puts "Batch raw: #{elapsed_raw.round(0)} μs"

puts "\nSpeedup (batch vs individual):"
puts "  With transform: #{speedup_with_transform}x faster"
puts "  Raw (no transform): #{speedup_raw}x faster"

puts "\n" + "=" * 60
puts "Analysis"
puts "=" * 60

if speedup_with_transform > 1.5
  puts "✓ Batch parsing is #{speedup_with_transform}x faster"
else
  puts "⚠ Batch parsing improvement: #{speedup_with_transform}x"
end

if speedup_raw > speedup_with_transform
  transform_overhead = ((elapsed - elapsed_raw) / elapsed * 100).round(1)
  puts "  Transformation adds #{transform_overhead}% overhead"
end

puts "\n" + "=" * 60
puts "Benchmark complete"
puts "=" * 60
