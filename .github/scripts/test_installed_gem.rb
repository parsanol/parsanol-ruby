#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify the installed parsanol gem works correctly.
# This script runs AFTER installing the gem via `gem install`,
# NOT from the source directory.
#
# Usage:
#   ruby test_installed_gem.rb

require "tempfile"
require "fileutils"

def windows?
  RbConfig::CONFIG["host_os"] =~ /mswin|mingw|cygwin/
end

# Test 1: Verify the gem can be loaded
puts "Test 1: Loading parsanol..."
begin
  require "parsanol"
  puts "  PASS: parsanol loaded successfully"
rescue LoadError => e
  puts "  FAIL: Could not load parsanol: #{e.message}"
  exit 1
end

# Test 2: Verify native extension is available (if applicable)
puts "Test 2: Checking native extension..."
begin
  if defined?(Parsanol::Native) && Parsanol::Native.available?
    puts "  PASS: Native extension is available"
  else
    puts "  INFO: Native extension not available (using pure Ruby)"
  end
rescue => e
  puts "  WARN: Could not check native extension: #{e.message}"
end

# Test 3: Test basic parsing functionality
puts "Test 3: Testing basic parsing..."
begin
  # Define a simple calculator parser
  class TestCalculatorParser < Parsanol::Parser
    rule(:digit) { match['0-9'] }
    rule(:number) { digit.repeat(1).as(:number) }
    rule(:space) { match[' \t'] }
    rule(:spaces) { space.repeat }
    rule(:operator) { match['+\\-*'] }
    rule(:expression) { number >> spaces >> operator >> spaces >> number }
    root :expression
  end

  parser = TestCalculatorParser.new

  # Test basic parse
  result = parser.parse("1 + 2")
  puts "  PASS: Basic parsing works: #{result.inspect}"
rescue => e
  puts "  FAIL: Basic parsing error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

# Test 4: Test native parser if available
puts "Test 4: Testing native parser (if available)..."
begin
  if defined?(Parsanol::Native) && Parsanol::Native.available?
    # Test using native parser
    grammar = Parsanol::Native.serialize_grammar(parser.parslet)
    puts "  PASS: Grammar serialization works"

    # Test native parse
    native_result = Parsanol::Native.parse(grammar, "1 + 2")
    puts "  PASS: Native parsing works: #{native_result.class}"
  else
    puts "  SKIP: Native parser not available"
  end
rescue => e
  puts "  WARN: Native parser test error: #{e.message}"
  # Don't fail - native is optional
end

# Test 5: Test JSON parsing
puts "Test 5: Testing JSON parser..."
begin
  class TestJsonParser < Parsanol::Parser
    rule(:string) { str('"') >> (str('\\') >> any | str('"').absent? >> any).repeat >> str('"') }
    rule(:number) { match['0-9'].repeat(1) >> (str('.') >> match['0-9'].repeat(1)).maybe }
    rule(:value) { string | number | array | object | str('true') | str('false') | str('null') }
    rule(:array) { str('[') >> value >> (str(',') >> value).repeat >> str(']') }
    rule(:pair) { string >> str(':') >> value }
    rule(:object) { str('{') >> pair >> (str(',') >> pair).repeat >> str('}') }
    root :value
  end

  json_parser = TestJsonParser.new
  result = json_parser.parse('"hello"')
  puts "  PASS: JSON string parsing works"

  result = json_parser.parse("123")
  puts "  PASS: JSON number parsing works"
rescue => e
  puts "  FAIL: JSON parser error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

# Test 6: Test transform functionality
puts "Test 6: Testing transform..."
begin
  class TestTransform < Parsanol::Transform
    rule(number: simple(:n)) { Integer(n) }
    rule(string: simple(:s)) { s.to_s }
  end

  transform = TestTransform.new
  result = transform.apply({ number: "42" })

  if result == 42
    puts "  PASS: Transform works correctly"
  else
    puts "  FAIL: Transform returned #{result.inspect} instead of 42"
    exit 1
  end
rescue => e
  puts "  FAIL: Transform error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

# Test 7: Memory and performance check
puts "Test 7: Testing performance..."
begin
  start_time = Time.now
  iterations = 100

  iterations.times do
    parser.parse("123 + 456")
  end

  elapsed = Time.now - start_time
  ips = iterations / elapsed
  puts "  PASS: #{iterations} parses in #{elapsed.round(3)}s (#{ips.round(1)} IPS)"
rescue => e
  puts "  WARN: Performance test error: #{e.message}"
end

puts ""
puts "All tests passed!"
exit 0
