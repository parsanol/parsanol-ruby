#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal reproduction script for Parslet compatibility bug
# Run from: /Users/mulgogi/src/parsanol/parsanol-ruby
#
# Usage: ruby spec/parslet_compatibility/minimal_reproduction.rb

require 'bundler/setup'
require 'parsanol'
require 'json'

puts "=" * 70
puts "PARSLET COMPATIBILITY BUG - MINIMAL REPRODUCTION"
puts "=" * 70

# ===========================================================================
# TEST CASE 1: Repetition with separator (most common pattern)
# ===========================================================================

class ListParser < Parsanol::Parser
  include Parsanol

  # Grammar mimics: listOf(X) = X (separator X)*
  # Example: parameter (',' parameter)*

  rule(:item) do
    match('[a-z]').as(:name)
  end

  rule(:separator) do
    str(',')
  end

  # This is the key pattern: (separator >> item).repeat
  rule(:list) do
    item.as(:first) >> (separator >> item).repeat.as(:rest)
  end

  root(:list)
end

puts "\n" + "=" * 70
puts "TEST CASE 1: Repetition with Separator"
puts "Input: 'a,b,c'"
puts "=" * 70

input1 = "a,b,c"
parser1 = ListParser.new

# Get Parslet output (expected)
begin
  parslet_result = parser1.parse(input1)
  puts "\n--- PARSLET OUTPUT (Expected) ---"
  puts JSON.pretty_generate(parslet_result)
rescue => e
  puts "Parslet error: #{e.message}"
end

# Get Parsanol output (actual)
begin
  grammar_json = Parsanol::Native.serialize_grammar(parser1.root)
  parsanol_result = Parsanol::Native.parse_parslet_compatible(parser1.root, input1)
  puts "\n--- PARSANOL OUTPUT (Actual) ---"
  puts JSON.pretty_generate(parsanol_result)
rescue => e
  puts "Parsanol error: #{e.message}"
end

# ===========================================================================
# TEST CASE 2: Single repetition element (should still be array)
# ===========================================================================

puts "\n" + "=" * 70
puts "TEST CASE 2: Single Repetition Element (should still be array)"
puts "Input: 'a+b'"
puts "=" * 70

class ExprParser < Parsanol::Parser
  include Parsanol

  rule(:factor) do
    match('[a-z]').as(:value)
  end

  rule(:operator) do
    str('+').as(:op)
  end

  # Expression: factor (operator factor)*
  rule(:expression) do
    factor.as(:left) >> (operator >> factor).as(:rhs).repeat
  end

  root(:expression)
end

input2 = "a+b"
parser2 = ExprParser.new

begin
  parslet_result2 = parser2.parse(input2)
  puts "\n--- PARSLET OUTPUT (Expected) ---"
  puts JSON.pretty_generate(parslet_result2)
  puts "\n  :rhs class: #{parslet_result2[:rhs].class}"
  puts "  :rhs length: #{parslet_result2[:rhs].length if parslet_result2[:rhs].is_a?(Array)}"
rescue => e
  puts "Parslet error: #{e.message}"
end

begin
  grammar_json2 = Parsanol::Native.serialize_grammar(parser2.root)
  parsanol_result2 = Parsanol::Native.parse_parslet_compatible(parser2.root, input2)
  puts "\n--- PARSANOL OUTPUT (Actual) ---"
  puts JSON.pretty_generate(parsanol_result2)
  puts "\n  :rhs class: #{parsanol_result2[:rhs].class if parsanol_result2[:rhs]}"
  puts "  :rhs length: #{parsanol_result2[:rhs].length if parsanol_result2[:rhs].is_a?(Array)}"
rescue => e
  puts "Parsanol error: #{e.message}"
end

# ===========================================================================
# TEST CASE 3: Multiple occurrences of same key
# ===========================================================================

puts "\n" + "=" * 70
puts "TEST CASE 3: Multiple Occurrences of Same Key"
puts "Input: 'a,b'"
puts "=" * 70

# Clear grammar cache to avoid conflicts with previous test cases
Parsanol::Native::Parser.clear_cache

class RepeatParser < Parsanol::Parser
  include Parsanol

  # Grammar: item.as(:x) (',' item.as(:x))*
  # Note: Both occurrences use the SAME label :x
  rule(:item) do
    match('[a-z]').as(:x)
  end

  rule(:list) do
    item >> (str(',') >> item).repeat
  end

  root(:list)
end

input3 = "a,b"
parser3 = RepeatParser.new

begin
  parslet_result3 = parser3.parse(input3)
  puts "\n--- PARSLET OUTPUT (Expected) ---"
  puts JSON.pretty_generate(parslet_result3)
  puts "\n  :x occurrences: #{parslet_result3[:x].inspect}"
rescue => e
  puts "Parslet error: #{e.message}"
end

begin
  grammar_json3 = Parsanol::Native.serialize_grammar(parser3.root)
  parsanol_result3 = Parsanol::Native.parse_parslet_compatible(parser3.root, input3)
  puts "\n--- PARSANOL OUTPUT (Actual) ---"
  puts JSON.pretty_generate(parsanol_result3)
  puts "\n  :x occurrences: #{parsanol_result3[:x].inspect if parsanol_result3[:x]}"
rescue => e
  puts "Parsanol error: #{e.message}"
end

# ===========================================================================
# SUMMARY
# ===========================================================================

puts "\n" + "=" * 70
puts "SUMMARY"
puts "=" * 70
puts <<~SUMMARY

  The bug is in: /Users/mulgogi/src/parsanol/parsanol-rs/src/portable/parslet_transform.rs

  Function: flatten_sequence (line ~203)

  Issue: When the same key appears multiple times (repetition pattern),
  the code MERGES them into a single hash, losing previous values.

  Expected: Repetition patterns should produce ARRAYS of hashes.
  Actual:   Repetition patterns are MERGED into single hashes.

  This affects any grammar using:
  - Parameter lists: param (',' param)*
  - Expression chains: term (operator term)*
  - Repeated elements: item.as(:x) (separator item.as(:x))*

  See full proposal at:
  /Users/mulgogi/src/parsanol/parsanol-ruby/PARSLET_COMPATIBILITY_BUG_PROPOSAL.md

SUMMARY
