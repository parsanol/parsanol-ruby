#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal reproduction script for Parslet compatibility bug
# Run from: /Users/mulgogi/src/parsanol/parsanol-ruby
#
# Usage: ruby spec/parslet_compatibility/minimal_reproduction.rb

require "bundler/setup"
require "parsanol"
require "json"





# ===========================================================================
# TEST CASE 1: Repetition with separator (most common pattern)
# ===========================================================================

class ListParser < Parsanol::Parser
  include Parsanol

  # Grammar mimics: listOf(X) = X (separator X)*
  # Example: parameter (',' parameter)*

  rule(:item) do
    match("[a-z]").as(:name)
  end

  rule(:separator) do
    str(",")
  end

  # This is the key pattern: (separator >> item).repeat
  rule(:list) do
    item.as(:first) >> (separator >> item).repeat.as(:rest)
  end

  root(:list)
end






input1 = "a,b,c"
parser1 = ListParser.new

# Get Parslet output (expected)
begin
  parslet_result = parser1.parse(input1)
  
  
rescue StandardError => e
  
end

# Get Parsanol output (actual)
begin
  Parsanol::Native.serialize_grammar(parser1.root)
  parsanol_result = Parsanol::Native::Parser.parse(parser1.root, input1)
  
  
rescue StandardError => e
  
end

# ===========================================================================
# TEST CASE 2: Single repetition element (should still be array)
# ===========================================================================






class ExprParser < Parsanol::Parser
  include Parsanol

  rule(:factor) do
    match("[a-z]").as(:value)
  end

  rule(:operator) do
    str("+").as(:op)
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
  
  
  
  
rescue StandardError => e
  
end

begin
  Parsanol::Native.serialize_grammar(parser2.root)
  parsanol_result2 = Parsanol::Native::Parser.parse(parser2.root, input2)
  
  
  
  
rescue StandardError => e
  
end

# ===========================================================================
# TEST CASE 3: Multiple occurrences of same key
# ===========================================================================






# Clear grammar cache to avoid conflicts with previous test cases
Parsanol::Native::Parser.clear_cache

class RepeatParser < Parsanol::Parser
  include Parsanol

  # Grammar: item.as(:x) (',' item.as(:x))*
  # Note: Both occurrences use the SAME label :x
  rule(:item) do
    match("[a-z]").as(:x)
  end

  rule(:list) do
    item >> (str(",") >> item).repeat
  end

  root(:list)
end

input3 = "a,b"
parser3 = RepeatParser.new

begin
  parslet_result3 = parser3.parse(input3)
  
  
  
rescue StandardError => e
  
end

begin
  Parsanol::Native.serialize_grammar(parser3.root)
  parsanol_result3 = Parsanol::Native::Parser.parse(parser3.root, input3)
  
  
  
rescue StandardError => e
  
end

# ===========================================================================
# SUMMARY
# ===========================================================================






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
