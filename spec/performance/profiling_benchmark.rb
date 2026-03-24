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

# Reset profile
Parsanol::Native.profile_reset

# Run parsing multiple times using NATIVE parser

100.times { Parsanol::Native::Parser.parse(parser, test_input) }

# Get profile
profile = Parsanol::Native.profile_stats

total_us = profile["total_parse_us"].to_i
if total_us == 0

end

profile["cache_hits"].to_i
profile["cache_misses"].to_i

total_matches = profile["lookup_matches"].to_i + profile["regex_matches"].to_i
if total_matches > 0
  ((profile["lookup_matches"].to_f / total_matches) * 100).round(1)

end

if profile["ast_nodes"].to_i > 0
  (profile["string_allocs"].to_f / profile["ast_nodes"].to_i * 100).round(1)

end

# Performance summary

if total_us > 0
  peg_pct = (profile["peg_match_us"].to_f / total_us * 100).round(1)
  ruby_pct = (profile["ast_to_ruby_us"].to_f / total_us * 100).round(1)

  if peg_pct > 50

  elsif ruby_pct > 40

  end

  if profile["cache_hit_rate"].to_i < 80

  end
end

# Large input test

Parsanol::Native.profile_reset
20.times { Parsanol::Native::Parser.parse(parser, large_input) }
Parsanol::Native.profile_stats
