#!/usr/bin/env ruby
# frozen_string_literal: true

# Parslet (legacy baseline) JSON acceptance harness: same corpus and
# protocol as the other SOTA harnesses. Acceptance-only grammar — no
# captures, so no `.as` overhead. `parslet` is the baseline parsanol
# was written to replace; it is pinned by the Gemfile.
require "parslet"
require "json"

class BenchmarkJson < Parslet::Parser
  root(:value)

  rule(:ws) { match("[ \t\r\n]").repeat }
  rule(:value) { object | array | string | number | boolean | null }
  rule(:object) do
    str("{") >> ws >>
      (pair >> (ws >> str(",") >> ws >> pair).repeat).maybe >>
      ws >> str("}")
  end
  rule(:pair) { string >> ws >> str(":") >> ws >> value }
  rule(:array) do
    str("[") >> ws >>
      (value >> (ws >> str(",") >> ws >> value).repeat).maybe >>
      ws >> str("]")
  end
  # Escapes are accepted generically (backslash + any char): the corpus
  # carries only RFC 8259-valid documents, so acceptance is equivalent.
  rule(:string) { str('"') >> ((str("\\") >> any) | match('[^"\\\\]')).repeat >> str('"') }
  rule(:number) do
    str("-").maybe >> match("[0-9]").repeat(1) >>
      (str(".") >> match("[0-9]").repeat(1)).maybe >>
      (match("[eE]") >> match("[-+]").maybe >> match("[0-9]").repeat(1)).maybe
  end
  rule(:boolean) { str("true") | str("false") }
  rule(:null) { str("null") }
end

def main
  corpus_path, iterations_arg = ARGV
  iterations = Integer(iterations_arg)
  corpus = JSON.parse(File.read(corpus_path))
  parser = BenchmarkJson.new
  docs = corpus.to_a

  docs.each do |name, text|
    parser.parse(text)
  rescue Parslet::ParseFailed => e
    abort "#{name} failed to parse: #{e.message.lines.first}"
  end

  samples = docs.map { |name, text| [name, text.bytesize, []] }
  iterations.times do
    docs.each_with_index do |(_, text), i|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      parser.parse(text)
      samples[i][2] << ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0)
    end
  end

  samples.each do |name, bytes, times|
    times.sort!
    median = times[times.length / 2]
    puts format("parslet,%s,%d,%d,%.6f", name, bytes, iterations, median)
  end
end

main
