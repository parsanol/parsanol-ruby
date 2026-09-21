# frozen_string_literal: true

require "benchmark"
require "parsanol"
require "parsanol/native"

# Exercise flatten on a deeper grammar: nested sequences, named
# repetitions, hashes — closer to coradoc's paragraph shape.
PARSER = Class.new(Parsanol::Parser) do
  rule(:line) do
    (match(/[^\n]/).repeat(1) | str("")).as(:text) >> str("\n").as(:line_break)
  end
  rule(:para) { line.repeat(1).as(:lines) >> match["\n"].repeat(0) }
  rule(:doc) { para.repeat(1) }

  root :doc
end.new

PARA = "the quick brown fox jumps over the lazy dog and then some more text for variety\n" * 5
DOC = (PARA + "\n") * 200

n = 50
ruby_res = PARSER.parse(DOC, mode: :ruby)
native_res = PARSER.parse(DOC, mode: :native)
unless ruby_res == native_res
  puts "DIVERGENT ruby vs native"
  puts "  ruby:   #{ruby_res.inspect[0, 200]}"
  puts "  native: #{native_res.inspect[0, 200]}"
  exit 1
end
puts "trees equal (#{ruby_res.length} lines)"

ruby_ms = Benchmark.realtime { n.times { PARSER.parse(DOC, mode: :ruby) } } * 1000 / n
native_ms = Benchmark.realtime { n.times { PARSER.parse(DOC, mode: :native) } } * 1000 / n
printf("ruby   %7.2f ms/parse\n", ruby_ms)
printf("native %7.2f ms/parse (%.2fx ruby)\n", native_ms, native_ms / ruby_ms)
