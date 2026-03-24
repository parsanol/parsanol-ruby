# frozen_string_literal: true

require "benchmark"
require "parslet"
require "parslet/native"





# First ensure native extension is loaded
unless Parsanol::Native.available?
  
  exit 1
end

class SimpleParser < Parsanol::Parser
  rule(:comma) { str(",") >> str(" ") }
  rule(:word) { match(/[a-z]/).repeat(1) }

  rule(:value) { word.as(:v) }
  rule(:list) { value >> (comma >> value).repeat }

  root(:list)
end

parser = SimpleParser.new
test_input = "one, two, three, four, five"

# Clear all caches
Parsanol::Native.clear_cache





# Profile if available (native extension method)
has_profiling = Parsanol::Native.respond_to?(:profile_reset)
Parsanol::Native.profile_reset if has_profiling

start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
Parsanol::Native::Parser.parse(parser, test_input)
cold_time = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                  :microsecond) - start

if has_profiling
  profile = Parsanol::Native.profile_stats
  
  
else
  
end






times = []
20.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  Parsanol::Native::Parser.parse(parser, test_input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                  :microsecond) - start
  times << elapsed
end

avg_warm = times.sum / times.length


speedup_cold_warm = cold_time > 0 && avg_warm > 0 ? (cold_time.to_f / avg_warm).round(0) : 0






# Use simple alphabetic inputs (Rust parser has issues with compound character classes)
words = %w[one two three four five six seven eight nine ten]
inputs = (0...50).map { |i|
 "#{words[i % 10]}, #{words[(i + 1) % 10]}, #{words[(i + 2) % 10]}"
}

# Individual
Parsanol::Native.clear_cache
individual_start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
inputs.each { |i| Parsanol::Native::Parser.parse(parser, i) }
individual_time = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                        :microsecond) - individual_start

# Batch with transform
batch_start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
Parsanol::Native.parse_batch_with_transform(parser, inputs)
batch_time = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                   :microsecond) - batch_start

# Batch raw (no transform)
Parsanol::Native.clear_cache
batch_raw_start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
Parsanol::Native.parse_batch_inputs(parser, inputs)
batch_raw_time = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                       :microsecond) - batch_raw_start












cold_time_ms = cold_time / 1000.0 # Convert to ms
warm_time_ms = avg_warm / 1000.0 # Convert to ms
speedup_warm = cold_time_ms > 0 && warm_time_ms > 0 ? (cold_time_ms / warm_time_ms).round(0) : 0



  COLD CACHE (first parse):
    Time: #{cold_time_ms.round(2)} ms

  WARM CACHE (repeated parsing):
    Time: #{warm_time_ms.round(4)} ms
    Speedup: #{speedup_warm}x faster

  BATCH (50 inputs, with transform):
    Time: #{(batch_time / 1000.0).round(2)} ms
    Speedup: #{(individual_time / batch_time).round(1)}x faster than individual

  OPTIMIZATIONS APPLIED:
    ✓ Two-level grammar caching
    ✓ Single-key hash optimization
    ✓ Array slicing optimization
    ✓ Batch transformation API
    ✓ Symbol key caching
    ✓ Frozen string constants
    ✓ Optimized flatten_sequence/flatten_repetition

  EXPRESSIR BENEFITS:
    ✓ NO native code changes needed
    ✓ Automatic performance improvement
    ✓ Reduced memory allocations

SUMMARY




