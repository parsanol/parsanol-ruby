#!/usr/bin/env ruby
# frozen_string_literal: true

# Parsanol Ruby API harness: the shipped artifact through the Ruby
# binding, both execution modes. `:native` is the fast lane (Rust
# engine via the extension); `:ruby` is the bytecode VM with its
# interpreter fallback. Both must accept every corpus document.
#
# Usage: bundle exec ruby run_ruby.rb <artifact.json> <corpus.json> <iterations>
require "parsanol"
require "json"

def timed(times)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  times << ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0)
end

def main
  artifact_path, corpus_path, iterations_arg = ARGV
  iterations = Integer(iterations_arg)
  artifact = Parsanol::PARG::Artifact.load(artifact_path)
  entry = artifact.envelope["default_entry"] || artifact.entries.first
  docs = JSON.parse(File.read(corpus_path)).to_a

  modes = { "parsanol-ruby-native" => :native, "parsanol-ruby-vm" => :ruby }
  docs.each do |name, text|
    modes.each_value do |mode|
      artifact.parse(entry, text, mode: mode)
    rescue StandardError => e
      abort "#{name} failed to parse in #{mode}: #{e.class}: #{e.message}"
    end
  end

  modes.each do |tool, mode|
    samples = docs.map { |name, text| [name, text.bytesize, []] }
    iterations.times do
      docs.each_with_index do |(_, text), i|
        timed(samples[i][2]) { artifact.parse(entry, text, mode: mode) }
      end
    end
    samples.each do |name, bytes, times|
      times.sort!
      puts format("%s,%s,%d,%d,%.6f", tool, name, bytes, iterations, times[times.length / 2])
    end
  end
end

main
