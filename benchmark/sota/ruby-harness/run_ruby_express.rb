#!/usr/bin/env ruby
# frozen_string_literal: true

# Parsanol Ruby API harness for the EXPRESS giant corpus: parses through
# expressir's production grammar (a parsanol DSL grammar, ~250 rules) in
# both engines — `:native` (Rust engine) and `:ruby` (VM + interpreter).
# This is the same pair run_ruby.rb measures for artifacts; EXPRESS has
# no artifact envelope because the grammar is DSL-built (see
# ../express/BUILT_FROM).
#
# The grammar lives in expressir, so run inside its bundle:
#   cd ~/src/lutaml/expressir && bundle exec \
#     ruby <parsanol>/benchmark/sota/ruby-harness/run_ruby_express.rb \
#     <corpus.json> <iterations>
require "expressir"
require "json"

def timed(times)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  times << ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0)
end

def main
  corpus_path, iterations_arg = ARGV
  iterations = Integer(iterations_arg)
  docs = JSON.parse(File.read(corpus_path)).to_a
  modes = { "parsanol-ruby-native" => :native, "parsanol-ruby-vm" => :ruby }

  modes.each_value do |mode|
    docs.each do |name, text|
      Expressir::Express::Grammar::Parser.cached_parser.parse(text, mode: mode)
    rescue StandardError => e
      abort "#{name} failed to parse in #{mode}: #{e.class}: #{e.message}"
    end
  end

  modes.each do |tool, mode|
    samples = docs.map { |name, text| [name, text.bytesize, []] }
    iterations.times do
      docs.each_with_index do |(_, text), i|
        timed(samples[i][2]) do
          Expressir::Express::Grammar::Parser.cached_parser.parse(text, mode: mode)
        end
      end
    end
    samples.each do |name, bytes, times|
      times.sort!
      puts format("%s,%s,%d,%d,%.6f", tool, name, bytes, iterations, times[times.length / 2])
    end
  end
end

main
