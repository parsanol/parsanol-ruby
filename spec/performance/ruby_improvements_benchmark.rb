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

# More complex parser to test caching
class ExpressionParser < Parsanol::Parser
  rule(:space) { match(/\s/).repeat(1) }
  rule(:spaces) { space.maybe }

  rule(:digit) { match(/[0-9]/) }
  rule(:number) { digit.repeat(1).as(:num) }

  rule(:lparen) { str("(") >> spaces }
  rule(:rparen) { str(")") >> spaces }

  rule(:plus) { str("+") >> spaces }
  rule(:minus) { str("-") >> spaces }
  rule(:times) { str("*") >> spaces }
  rule(:divide) { str("/") >> spaces }

  rule(:factor) { number | (lparen >> expression >> rparen) }
  rule(:term) { factor >> ((times | divide) >> factor).repeat }
  rule(:expression) { term >> ((plus | minus) >> term).repeat }

  root(:expression)
end

parser = SimpleParser.new
expr_parser = ExpressionParser.new

# Test inputs
simple_input = "one, two, three, four, five"
complex_input = "1 + 2 * 3 - 4 / 5"
large_input = (1..100).map { |_i| "word" }.join(", ")

# Clear cache first
Parsanol::Native.clear_cache

# ============================================================================
# Test 1: Simple parser - first parse (cold cache)
# ============================================================================

Parsanol::Native.profile_reset
Parsanol::Native::Parser.parse(parser, simple_input)
Parsanol::Native.profile_stats

# ============================================================================
# Test 2: Simple parser - repeated parses (warm cache)
# ============================================================================

Parsanol::Native.profile_reset
Parsanol::Native.clear_cache

times = []
100.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  Parsanol::Native::Parser.parse(parser, simple_input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                  :microsecond) - start
  times << elapsed
end

times.sum / times.length
Parsanol::Native.profile_stats

# ============================================================================
# Test 3: Complex parser (more grammar atoms)
# ============================================================================

Parsanol::Native.profile_reset
Parsanol::Native.clear_cache

times = []
100.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  Parsanol::Native::Parser.parse(expr_parser, complex_input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                  :microsecond) - start
  times << elapsed
end

times.sum / times.length
Parsanol::Native.profile_stats

# ============================================================================
# Test 4: Large input
# ============================================================================

Parsanol::Native.profile_reset
Parsanol::Native.clear_cache

times = []
20.times do
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :microsecond)
  Parsanol::Native::Parser.parse(parser, large_input)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC,
                                  :microsecond) - start
  times << elapsed
end

times.sum / times.length
Parsanol::Native.profile_stats

# ============================================================================
# Summary
# ============================================================================
