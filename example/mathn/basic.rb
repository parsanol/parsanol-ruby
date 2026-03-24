# frozen_string_literal: true

# Demonstrates that we have a compatibility fix to mathn's weird idea of
# integer mathematics.
# Originally contributed to Parslet, ported to Parsanol as an example.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require "parsanol/parslet"
require "parsanol/convenience"
include Parsanol::Parslet

def attempt_parse
  possible_whitespace = match['\s'].repeat

  cephalopod =
    str("octopus") |
    str("squid")

  parenthesized_cephalopod =
    str("(") >>
    possible_whitespace >>
    cephalopod >>
    possible_whitespace >>
    str(")")

  parser =
    possible_whitespace >>
    parenthesized_cephalopod >>
    possible_whitespace

  # This parse fails, but that is not the point. When mathn is in the current
  # ruby environment, it modifies integer division in a way that makes
  # parslet loop indefinitely.
  parser.parse %{(\nsqeed)\n}
rescue Parsanol::ParseFailed
end

attempt_parse
puts "it terminates before we require mathn"

puts "requiring mathn now"
# mathn was deprecated as of Ruby 2.5
require "mathn" if RUBY_VERSION.gsub(/[^\d]/, "").to_i < 250
puts "and trying again (will hang without the fix)"
attempt_parse # but it doesn't terminate after requiring mathn
puts "okay!"
