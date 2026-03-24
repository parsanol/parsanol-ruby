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

# Test input
test_input = "one, two, three, four, five, six, seven, eight, nine, ten"
large_input = (1..100).map { |_i| "word" }.join(", ")

# ============================================================================
# Test 1: Without grammar caching (parse_parslet_compatible)
# ============================================================================

Parsanol::Native.profile_reset
100.times { Parsanol::Native::Parser.parse(parser, test_input) }
profile_no_cache = Parsanol::Native.profile_stats

# ============================================================================
# Test 2: With grammar caching (parse_with_grammar)
# ============================================================================

# Pre-serialize grammar ONCE
grammar_json = Parsanol::Native.send(:serialize_grammar, parser)

Parsanol::Native.profile_reset
100.times { Parsanol::Native.parse(grammar_json, test_input) }
profile_cached = Parsanol::Native.profile_stats

# ============================================================================
# Comparison
# ============================================================================

total_no_cache = profile_no_cache["total_parse_us"].to_i
total_cached = profile_cached["total_parse_us"].to_i

if total_no_cache > 0 && total_cached > 0
  ((total_no_cache - total_cached).to_f / total_no_cache * 100).round(1)
  (total_no_cache.to_f / total_cached).round(2)

end

# ============================================================================
# Large input test with caching
# ============================================================================

Parsanol::Native.profile_reset
20.times { Parsanol::Native.parse(grammar_json, large_input) }
Parsanol::Native.profile_stats
