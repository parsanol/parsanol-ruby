#!/usr/bin/env ruby
# frozen_string_literal: true

# Email address parser with sanitization support.
# Originally contributed to Parslet, ported to Parsanol as an example.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require "parsanol/parslet"
require "parsanol/convenience"

class EmailParser < Parsanol::Parser
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }
  rule(:dash?) { match["_-"].maybe }

  rule(:at) do
    str("@") |
      (dash? >> (str("at") | str("AT")) >> dash?)
  end
  rule(:dot) do
    str(".") |
      (dash? >> (str("dot") | str("DOT")) >> dash?)
  end

  rule(:word) { match("[a-z0-9]").repeat(1).as(:word) >> space? }
  rule(:separator) { (dot.as(:dot) >> space?) | space }
  rule(:words) { word >> (separator >> word).repeat }

  rule(:email) do
    (words.as(:username) >> space? >> at >> space? >> words).as(:email)
  end

  root(:email)
end

class EmailSanitizer < Parsanol::Transform
  rule(dot: simple(:dot), word: simple(:word)) { ".#{word}" }
  rule(word: simple(:word)) { word }

  rule(username: sequence(:username)) { "#{username.join}@" }
  rule(username: simple(:username)) { "#{username}@" }

  rule(email: sequence(:email)) { email.join }
end

parser = EmailParser.new
sanitizer = EmailSanitizer.new

input = ARGV[0] || begin
  default = "a.b.c.d@gmail.com"
  warn "usage: #{$PROGRAM_NAME} \"EMAIL_ADDR\""
  $stdout.puts "since you haven't specified any EMAIL_ADDR, for testing purposes we're using #{default}"
  default
end

p sanitizer.apply(parser.parse_with_debug(input))
