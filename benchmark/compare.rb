#!/usr/bin/env ruby
# frozen_string_literal: true

# Compare parslet vs parsanol :ruby vs parsanol native on the issue #25
# AsciiChem-shape grammar. Prints the table used in PR descriptions.
#
#   ruby benchmark/compare.rb

require "bundler/setup" if File.exist?("Gemfile.lock")
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "benchmark"
require "parslet"
require "parsanol"
require "parsanol/parslet"

module Bench
  class PParslet < Parslet::Parser
    rule(:element) { match("[A-Z]") >> match("[a-z]").maybe }
    rule(:subscript) { str("_") >> match("\\d").repeat(1) }
    rule(:superscript) { str("^") >> match("[0-9+-]").repeat(1) }
    rule(:atom) { element >> subscript.maybe >> superscript.maybe }
    rule(:bond) { match("[-=#]") }
    rule(:molecule) { atom >> (bond.maybe >> atom).repeat }
    root(:molecule)
  end

  class FParser < Parsanol::Parslet::Parser
    rule(:element) { match(/[A-Z]/) >> match(/[a-z]/).maybe }
    rule(:subscript) { str("_") >> match(/\d/).repeat(1) }
    rule(:superscript) { str("^") >> match(/[0-9+-]/).repeat(1) }
    rule(:atom) { element >> subscript.maybe >> superscript.maybe }
    rule(:bond) { match(/[-=#]/) }
    rule(:molecule) { atom >> (bond.maybe >> atom).repeat }
    root(:molecule)
  end
end

INPUTS = %w[
  SO_4^2- H_2O CH_3-CH_2-OH HC#CH Na^+ Cl^-1 Ca^2+
  C_6H_12O_6 H_2O-H_2O CH_3-CH_2-CH_2-CH_3
].freeze
BIG = 1000.times.map { INPUTS.sample }.join("-")
N_SMALL = 300
N_BIG = 20

fp = Bench::FParser.new
# sanity
INPUTS.each do |i|
  a = Bench::PParslet.new.parse(i).inspect
  b = fp.parse(i, mode: :ruby).inspect
  c = fp.parse(i, mode: :native).inspect
  raise "ruby/native mismatch on #{i}" if b != c
  # parslet output is reference for the ruby path only
  raise "parslet/ruby mismatch on #{i}: #{a} vs #{b}" if a != b
end

puts "native available: #{Parsanol::Native.available?}"
puts "parsanol #{Parsanol::VERSION}"
puts
puts "== small inputs (#{INPUTS.size} x #{N_SMALL}) =="
Benchmark.bm(18) do |x|
  x.report("parslet") { N_SMALL.times { INPUTS.each { |i| Bench::PParslet.new.parse(i) } } }
  x.report("parsanol :ruby") { N_SMALL.times { INPUTS.each { |i| fp.parse(i, mode: :ruby) } } }
  x.report("parsanol :native") { N_SMALL.times { INPUTS.each { |i| fp.parse(i, mode: :native) } } }
end

puts
puts "== large input (#{BIG.bytesize} bytes x #{N_BIG}) =="
Benchmark.bm(18) do |x|
  x.report("parslet") { N_BIG.times { Bench::PParslet.new.parse(BIG) } }
  x.report("parsanol :ruby") { N_BIG.times { fp.parse(BIG, mode: :ruby) } }
  x.report("parsanol :native") { N_BIG.times { fp.parse(BIG, mode: :native) } }
end
