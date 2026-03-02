# frozen_string_literal: true

require "benchmark"
require "parslet"
require "parslet/native"

puts "=" * 60
puts "Parsanol Profiling Analysis (Native Parser)"
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

# Test input
test_input = "one, two, three, four, five, six, seven, eight, nine, ten"
large_input = (1..100).map { |i| "word" }.join(", ")

# Reset profile
Parsanol::Native.profile_reset

# Run parsing multiple times using NATIVE parser
puts "\nRunning 100 native parses..."
100.times { Parsanol::Native.parse_parslet_compatible(parser, test_input) }

# Get profile
profile = Parsanol::Native.profile_stats

puts "\n" + "-" * 60
puts "Profile Results"
puts "-" * 60

total_us = profile["total_parse_us"].to_i
if total_us == 0
  puts "\nWARNING: No timing data collected. Parser may be using Ruby implementation."
else
  puts "\nTiming (microseconds):"
  puts "  Total parse time: #{total_us} us"
  puts "  Grammar parsing:   #{profile["grammar_parse_us"]} us (#{((profile["grammar_parse_us"].to_f / total_us) * 100).round(1)}%)"
  puts "  PEG matching:      #{profile["peg_match_us"]} us (#{((profile["peg_match_us"].to_f / total_us) * 100).round(1)}%)"
  puts "  AST to Ruby:       #{profile["ast_to_ruby_us"]} us (#{((profile["ast_to_ruby_us"].to_f / total_us) * 100).round(1)}%)"
end

total_cache = profile["cache_hits"].to_i + profile["cache_misses"].to_i
puts "\nCache Performance:"
puts "  Hits:   #{profile["cache_hits"]}"
puts "  Misses: #{profile["cache_misses"]}"
puts "  Hit rate: #{profile["cache_hit_rate"]}%"

puts "\nMatch Performance:"
puts "  Lookup matches: #{profile["lookup_matches"]}"
puts "  Regex matches:  #{profile["regex_matches"]}"
total_matches = profile["lookup_matches"].to_i + profile["regex_matches"].to_i
if total_matches > 0
  lookup_pct = ((profile["lookup_matches"].to_f / total_matches) * 100).round(1)
  puts "  Fast path: #{lookup_pct}%"
end

puts "\nAllocation Stats:"
puts "  AST nodes:        #{profile["ast_nodes"]}"
puts "  String allocs:    #{profile["string_allocs"]}"
if profile["ast_nodes"].to_i > 0
  str_per_node = (profile["string_allocs"].to_f / profile["ast_nodes"].to_i * 100).round(1)
  puts "  Strings/node:     #{str_per_node}%"
end

# Performance summary
puts "\n" + "=" * 60
puts "Analysis Summary"
puts "=" * 60

if total_us > 0
  peg_pct = (profile["peg_match_us"].to_f / total_us * 100).round(1)
  ruby_pct = (profile["ast_to_ruby_us"].to_f / total_us * 100).round(1)

  puts "\nHot Path Analysis:"
  if peg_pct > 50
    puts "  ⚠️  PEG matching is the bottleneck (#{peg_pct}%)"
    puts "     -> Consider optimizing grammar or using tokens"
  elsif ruby_pct > 40
    puts "  ⚠️  AST to Ruby conversion is the bottleneck (#{ruby_pct}%)"
    puts "     -> Consider batch conversion or fewer allocations"
  else
    puts "  ✓  Time is distributed, good balance"
  end

  if profile["cache_hit_rate"].to_i < 80
    puts "\n  ⚠️  Cache hit rate is low (#{profile["cache_hit_rate"]}%)"
    puts "     -> Consider larger cache or different strategy"
  else
    puts "\n  ✓  Cache hit rate is good (#{profile["cache_hit_rate"]}%)"
  end
else
  puts "\nNo timing data available for analysis."
end

# Large input test
puts "\n" + "-" * 60
puts "Large Input Test (#{large_input.length} chars)"
puts "-" * 60

Parsanol::Native.profile_reset
20.times { Parsanol::Native.parse_parslet_compatible(parser, large_input) }
profile_large = Parsanol::Native.profile_stats

puts "\nTiming:"
puts "  Total parse time: #{profile_large["total_parse_us"]} us"
puts "  PEG matching:      #{profile_large["peg_match_us"]} us"
puts "  AST to Ruby:       #{profile_large["ast_to_ruby_us"]} us"

puts "\nCache:"
puts "  Hit rate: #{profile_large["cache_hit_rate"]}%"

puts "\n" + "=" * 60
puts "Profiling complete"
puts "=" * 60
