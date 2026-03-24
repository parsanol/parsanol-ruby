# frozen_string_literal: true

require "benchmark"
require "parslet"
require "parslet/native"

# First ensure native extension is loaded
unless Parsanol::Native.available?

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
inputs = (1..50).map { |i| "item#{i}, item#{i + 1}, item#{i + 2}" }

# ============================================================================
# Test 1: Individual parsing (current approach)
# ============================================================================

Parsanol::Native.clear_cache

individual_times = []
inputs.each do |input|
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  Parsanol::Native::Parser.parse(parser, input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                  :microsecond) - start
  individual_times << elapsed
end

# ============================================================================
# Test 2: Batch parsing with transform
# ============================================================================

Parsanol::Native.clear_cache

start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
Parsanol::Native.parse_batch_with_transform(parser, inputs)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start

# ============================================================================
# Test 3: Raw parsing (no transform)
# ============================================================================

Parsanol::Native.clear_cache

start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
Parsanol::Native.parse_batch(parser, inputs)
elapsed_raw = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                    :microsecond) - start

# ============================================================================
# Comparison
# ============================================================================

total_individual = individual_times.sum
speedup_with_transform = (total_individual / elapsed).round(2)
speedup_raw = (total_individual / elapsed_raw).round(2)

if speedup_with_transform > 1.5

end

if speedup_raw > speedup_with_transform
  ((elapsed - elapsed_raw) / elapsed * 100).round(1)

end
