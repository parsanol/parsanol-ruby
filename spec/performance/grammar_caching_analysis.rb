# frozen_string_literal: true

require 'benchmark'
require 'parslet'
require 'parslet/native'

puts '=' * 60
puts 'Parsanol Grammar Caching Analysis'
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

parser = SimpleParser.new

# Test input
test_input = 'one, two, three, four, five, six, seven, eight, nine, ten'
large_input = (1..100).map { |_i| 'word' }.join(', ')

# ============================================================================
# Test 1: Without grammar caching (parse_parslet_compatible)
# ============================================================================
puts "\n#{'-' * 60}"
puts 'Test 1: parse_parslet_compatible (NO caching)'
puts '-' * 60

Parsanol::Native.profile_reset
100.times { Parsanol::Native.parse_parslet_compatible(parser, test_input) }
profile_no_cache = Parsanol::Native.profile_stats

puts "\nTiming (microseconds):"
puts "  Total: #{profile_no_cache['total_parse_us']} us"
puts "  Grammar JSON: #{profile_no_cache['grammar_parse_us']} us"
puts "  PEG match: #{profile_no_cache['peg_match_us']} us"

# ============================================================================
# Test 2: With grammar caching (parse_with_grammar)
# ============================================================================
puts "\n#{'-' * 60}"
puts 'Test 2: parse_with_grammar (cached grammar)'
puts '-' * 60

# Pre-serialize grammar ONCE
grammar_json = Parsanol::Native.send(:serialize_grammar, parser)
puts "Grammar JSON size: #{grammar_json.length} chars"

Parsanol::Native.profile_reset
100.times { Parsanol::Native.parse(grammar_json, test_input) }
profile_cached = Parsanol::Native.profile_stats

puts "\nTiming (microseconds):"
puts "  Total: #{profile_cached['total_parse_us']} us"
puts "  Grammar JSON: #{profile_cached['grammar_parse_us']} us"
puts "  PEG match: #{profile_cached['peg_match_us']} us"

# ============================================================================
# Comparison
# ============================================================================
puts "\n#{'=' * 60}"
puts 'Comparison'
puts '=' * 60

total_no_cache = profile_no_cache['total_parse_us'].to_i
total_cached = profile_cached['total_parse_us'].to_i

if total_no_cache > 0 && total_cached > 0
  improvement = ((total_no_cache - total_cached).to_f / total_no_cache * 100).round(1)
  speedup = (total_no_cache.to_f / total_cached).round(2)

  puts "\nTotal time (100 parses):"
  puts "  Without caching: #{total_no_cache} us"
  puts "  With caching:   #{total_cached} us"
  puts "  Improvement:    #{improvement}%"
  puts "  Speedup:        #{speedup}x"

  puts "\nGrammar JSON parsing:"
  puts "  Without caching: #{profile_no_cache['grammar_parse_us']} us"
  puts "  With caching:   #{profile_cached['grammar_parse_us']} us"

  puts "\nCache performance:"
  puts "  Hits: #{profile_cached['cache_hits']}"
  puts "  Misses: #{profile_cached['cache_misses']}"
  puts "  Hit rate: #{profile_cached['cache_hit_rate']}%"
else
  puts "\nWARNING: No timing data available"
end

# ============================================================================
# Large input test with caching
# ============================================================================
puts "\n#{'-' * 60}"
puts 'Large Input Test (cached grammar)'
puts '-' * 60

Parsanol::Native.profile_reset
20.times { Parsanol::Native.parse(grammar_json, large_input) }
profile_large = Parsanol::Native.profile_stats

puts "\nTiming (#{large_input.length} chars, 20 parses):"
puts "  Total: #{profile_large['total_parse_us']} us"
puts "  Grammar JSON: #{profile_large['grammar_parse_us']} us"
puts "  PEG match: #{profile_large['peg_match_us']} us"
puts "  Cache hit rate: #{profile_large['cache_hit_rate']}%"

puts "\n#{'=' * 60}"
puts 'Analysis complete'
puts '=' * 60
