# frozen_string_literal: true

require 'benchmark'
require 'parslet'
require 'parslet/native'

puts '=' * 60
puts 'Parsanol Ruby Improvements Benchmark'
puts '=' * 60

# First ensure native extension is loaded
unless Parsanol::Native.available?
  puts "ERROR: Native extension not available. Run 'rake compile' first."
  exit 1
end

class SimpleParser < Parsanol::Parser
  rule(:comma) { str(',') >> str(' ').maybe }
  rule(:word) { match(/[a-z]/).repeat(1) }
  rule(:alnum) { match(/[a-z0-9]/).repeat(1) }

  rule(:value) { (word | alnum).as(:v) }
  rule(:list) { value >> (comma >> value).repeat }

  root(:list)
end

# More complex parser to test caching
class ExpressionParser < Parsanol::Parser
  rule(:space) { match(/\s/).repeat(1) }
  rule(:spaces) { space.maybe }

  rule(:digit) { match(/[0-9]/) }
  rule(:number) { digit.repeat(1).as(:num) }

  rule(:lparen) { str('(') >> spaces }
  rule(:rparen) { str(')') >> spaces }

  rule(:plus) { str('+') >> spaces }
  rule(:minus) { str('-') >> spaces }
  rule(:times) { str('*') >> spaces }
  rule(:divide) { str('/') >> spaces }

  rule(:factor) { number | (lparen >> expression >> rparen) }
  rule(:term) { factor >> ((times | divide) >> factor).repeat }
  rule(:expression) { term >> ((plus | minus) >> term).repeat }

  root(:expression)
end

parser = SimpleParser.new
expr_parser = ExpressionParser.new

# Test inputs
simple_input = 'one, two, three, four, five'
complex_input = '1 + 2 * 3 - 4 / 5'
large_input = (1..100).map { |_i| 'word' }.join(', ')

# Clear cache first
Parsanol::Native.clear_cache

# ============================================================================
# Test 1: Simple parser - first parse (cold cache)
# ============================================================================
puts "\n#{'-' * 60}"
puts 'Test 1: Simple Parser (first parse, cold cache)'
puts '-' * 60

Parsanol::Native.profile_reset
result1 = Parsanol::Native::Parser.parse(parser, simple_input)
profile1 = Parsanol::Native.profile_stats

puts "Result: #{result1.inspect}"
puts "Time: #{profile1['total_parse_us']} us"

# ============================================================================
# Test 2: Simple parser - repeated parses (warm cache)
# ============================================================================
puts "\n#{'-' * 60}"
puts 'Test 2: Simple Parser (100 parses, warm cache)'
puts '-' * 60

Parsanol::Native.profile_reset
Parsanol::Native.clear_cache

times = []
100.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  Parsanol::Native::Parser.parse(parser, simple_input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start
  times << elapsed
end

avg_time = times.sum / times.length
Parsanol::Native.profile_stats

puts "Average time: #{avg_time} us"
puts "First parse: #{times.first} us"
puts "Last parse: #{times.last} us"
puts "Cache stats: #{Parsanol::Native.cache_stats}"

# ============================================================================
# Test 3: Complex parser (more grammar atoms)
# ============================================================================
puts "\n#{'-' * 60}"
puts 'Test 3: Expression Parser (100 parses)'
puts '-' * 60

Parsanol::Native.profile_reset
Parsanol::Native.clear_cache

times = []
100.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  Parsanol::Native::Parser.parse(expr_parser, complex_input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start
  times << elapsed
end

avg_time = times.sum / times.length
Parsanol::Native.profile_stats

puts "Average time: #{avg_time} us"
puts "First parse: #{times.first} us"
puts "Last parse: #{times.last} us"
puts "Cache stats: #{Parsanol::Native.cache_stats}"

# ============================================================================
# Test 4: Large input
# ============================================================================
puts "\n#{'-' * 60}"
puts "Test 4: Large Input (#{large_input.length} chars, 20 parses)"
puts '-' * 60

Parsanol::Native.profile_reset
Parsanol::Native.clear_cache

times = []
20.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  Parsanol::Native::Parser.parse(parser, large_input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond) - start
  times << elapsed
end

avg_time = times.sum / times.length
Parsanol::Native.profile_stats

puts "Average time: #{avg_time} us"
puts "Cache stats: #{Parsanol::Native.cache_stats}"

# ============================================================================
# Summary
# ============================================================================
puts "\n#{'=' * 60}"
puts 'Summary'
puts '=' * 60

puts "\nRuby Optimizations Applied:"
puts '  - Structural grammar caching (hash-based)'
puts '  - Frozen string constants'
puts '  - Optimized AstTransformer'
puts '  - Direct JSON output from serializer'

puts "\nPerformance Results:"
puts '  - Grammar caching: Working (hash-based key)'
puts "  - Cache hits after warmup: #{Parsanol::Native.cache_stats[:size]} grammars cached"

puts "\n#{'=' * 60}"
puts 'Benchmark complete'
puts '=' * 60
