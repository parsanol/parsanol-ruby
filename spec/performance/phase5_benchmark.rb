# frozen_string_literal: true

require "benchmark"
require "parslet"
require "parslet/native"





# First ensure native extension is loaded
unless Parsanol::Native.available?
  
  exit 1
end

# A larger parser to show the impact
class MediumParser < Parsanol::Parser
  rule(:space) { match(/\s/).repeat(1) }
  rule(:space?) { space.maybe }

  rule(:digit) { match(/[0-9]/) }
  rule(:letter) { match(/[a-zA-Z]/) }
  rule(:alnum) { match(/[a-zA-Z0-9]/) }

  rule(:integer) { digit.repeat(1) }
  rule(:float) { digit.repeat(1) >> str(".") >> digit.repeat(1) }
  rule(:number) { (float | integer).as(:number) }

  rule(:string) { str('"') >> match(/[^"]/).repeat.as(:string) >> str('"') }

  rule(:identifier) { (letter >> alnum.repeat).as(:identifier) }

  rule(:atom) { number | string | identifier }

  rule(:add_op) { str("+") | str("-") }
  rule(:mul_op) { str("*") | str("/") }

  rule(:mul_expr) { atom >> (space? >> mul_op >> space? >> atom).repeat }
  rule(:add_expr) {
 mul_expr >> (space? >> add_op >> space? >> mul_expr).repeat
}
  rule(:expression) { add_expr.as(:expression) }

  rule(:comma) { str(",") >> space? }
  rule(:arg_list) { expression >> (comma >> expression).repeat }
  rule(:function_call) {
 identifier >> str("(") >> space? >> arg_list.as(:args).maybe >> str(")")
}

  rule(:statement) { (expression | function_call).as(:statement) >> str(";") }
  rule(:program) { space? >> statement.repeat.as(:statements) >> space? }

  root(:program)
end

parser = MediumParser.new
test_input = 'x = 1 + 2 * 3; y = "hello"; func(x, y, 42);'





Parsanol::Native.clear_cache

start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
result = Parsanol::Native::Parser.parse(parser, test_input)
cold_time = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                  :microsecond) - start








# The key improvement: object_id cache avoids grammar structure traversal
times = []
50.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  result = Parsanol::Native::Parser.parse(parser, test_input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                  :microsecond) - start
  times << elapsed
end

avg_warm = times.sum / times.length








inputs = [
  "a = 1;",
  "b = 2 + 3;",
  "c = x * y;",
  "func(a, b, c);",
  'result = "test";',
]

Parsanol::Native.clear_cache

# First parse (cold)
start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
inputs.each { |i| Parsanol::Native::Parser.parse(parser, i) }
first_batch = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                    :microsecond) - start

# Second batch (warm)
start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
inputs.each { |i| Parsanol::Native::Parser.parse(parser, i) }
second_batch = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                     :microsecond) - start










speedup = cold_time > 0 && avg_warm > 0 ? (cold_time.to_f / avg_warm).round(0) : 0



  COLD CACHE (first parse):
    Time: #{cold_time} μs

  WARM CACHE (repeated parsing):
    Time: #{avg_warm.round(2)} μs
    Speedup: #{speedup}x faster

  TWO-LEVEL CACHE:
    Level 1 (object_id → hash): #{Parsanol::Native.cache_stats[:hash_cache_size]} entries
    Level 2 (hash → json): #{Parsanol::Native.cache_stats[:grammar_cache_size]} entries

  OPTIMIZATION APPLIED:
    ✓ Two-level grammar caching
    ✓ Avoids grammar structure traversal on repeated parses
    ✓ Shares grammar JSON across parser instances with same structure

SUMMARY




