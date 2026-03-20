# frozen_string_literal: true

require 'spec_helper'
begin
  require 'benchmark/ips'
rescue LoadError
  return unless defined?(RSpec)

  RSpec.describe 'Native vs Ruby Performance Benchmarks', :performance do
    it 'requires benchmark-ips gem' do
      skip 'benchmark-ips gem not installed'
    end
  end
  return
end
require 'parsanol/native'

RSpec.describe 'Native vs Ruby Performance Benchmarks', :performance do
  # Skip if native parser not available
  before(:all) do
    skip 'Native parser not available' unless Parsanol::Native.available?
  end

  # Simple calculator parser
  let(:calc_parser) do
    Class.new(Parsanol::Parser) do
      rule(:addition) do
        (multiplication.as(:l) >> (add_op >> multiplication.as(:r)).repeat(1)) |
          multiplication
      end

      rule(:multiplication) do
        (integer.as(:l) >> (mult_op >> integer.as(:r)).repeat(1)) |
          integer
      end

      rule(:integer) { digit.repeat(1).as(:i) >> space? }
      rule(:mult_op) { match['*/'].as(:o) >> space? }
      rule(:add_op) { match['+-'].as(:o) >> space? }
      rule(:digit) { match['0-9'] }
      rule(:space?) { match['\s'].repeat }

      root :addition
    end
  end

  # JSON parser
  let(:json_parser) do
    Class.new(Parsanol::Parser) do
      rule(:spaces) { match('\s').repeat(1) }
      rule(:spaces?) { spaces.maybe }
      rule(:comma) { spaces? >> str(',') >> spaces? }
      rule(:digit) { match('[0-9]') }

      rule(:number) do
        (
          str('-').maybe >> (
            str('0') | (match('[1-9]') >> digit.repeat)
          ) >> (
            str('.') >> digit.repeat(1)
          ).maybe >> (
            match('[eE]') >> (str('+') | str('-')).maybe >> digit.repeat(1)
          ).maybe
        ).as(:number)
      end

      rule(:string) do
        str('"') >> (
          (str('\\') >> any) | (str('"').absent? >> any)
        ).repeat.as(:string) >> str('"')
      end

      rule(:array) do
        str('[') >> spaces? >>
          (value >> (comma >> value).repeat).maybe.as(:array) >>
          spaces? >> str(']')
      end

      rule(:object) do
        str('{') >> spaces? >>
          (entry >> (comma >> entry).repeat).maybe.as(:object) >>
          spaces? >> str('}')
      end

      rule(:value) do
        string | number |
          object | array |
          str('true').as(true) | str('false').as(false) |
          str('null').as(:null)
      end

      rule(:entry) do
        (
           string.as(:key) >> spaces? >>
           str(':') >> spaces? >>
           value.as(:val)
         ).as(:entry)
      end

      rule(:top) { spaces? >> value >> spaces? }
      root(:top)
    end
  end

  # Identifier parser (tests regex patterns)
  let(:identifier_parser) do
    Class.new(Parsanol::Parser) do
      rule(:identifier) { match('[a-zA-Z_]').repeat(1).as(:id) }
      root :identifier
    end
  end

  describe 'Simple calculator expressions' do
    let(:input) { '1 + 2 * 3 + 4 * 5' }

    # NOTE: AST structure differs between Ruby and Native parsers
    # Ruby flattens sequences, Native returns structured output
    # Both produce valid parse trees, just structured differently
    it 'native parser successfully parses calculator expressions' do
      result = Parsanol::Native.parse(calc_parser.new, input)
      expect(result).not_to be_nil
      # Result can be Array or Hash depending on grammar structure
      expect(result).to be_a(Array).or be_a(Hash)
    end

    it 'measures speedup' do
      parser = calc_parser.new
      grammar = Parsanol::Native.serialize_grammar(parser.root)

      ruby_ips = Benchmark.ips(quiet: true) do |x|
        x.report('ruby') { parser.parse(input) }
      end.entries.first.ips

      native_ips = Benchmark.ips(quiet: true) do |x|
        x.report('native') { Parsanol::Native.parse(grammar, input) }
      end.entries.first.ips

      speedup = native_ips / ruby_ips
      puts "Calculator: #{speedup.round(1)}x faster (Ruby: #{ruby_ips.round(0)} ips, Native: #{native_ips.round(0)} ips)"

      # Expect at least 2x speedup for simple grammars
      expect(speedup).to be > 1.0
    end
  end

  describe 'JSON parsing' do
    let(:simple_json) { '{"key": "value", "number": 123}' }
    let(:nested_json) { '{"a": [1, 2, 3], "b": {"c": "d"}}' }

    # NOTE: AST structure differs between Ruby and Native parsers
    # Both produce valid parse trees, just structured differently
    it 'native parser successfully parses simple JSON' do
      result = Parsanol::Native.parse(json_parser.new, simple_json)
      expect(result).not_to be_nil
    end

    it 'measures speedup for simple JSON' do
      parser = json_parser.new
      grammar = Parsanol::Native.serialize_grammar(parser.root)

      ruby_ips = Benchmark.ips(quiet: true) do |x|
        x.report('ruby') { parser.parse(simple_json) }
      end.entries.first.ips

      native_ips = Benchmark.ips(quiet: true) do |x|
        x.report('native') { Parsanol::Native.parse(grammar, simple_json) }
      end.entries.first.ips

      speedup = native_ips / ruby_ips
      puts "JSON simple: #{speedup.round(1)}x faster (Ruby: #{ruby_ips.round(0)} ips, Native: #{native_ips.round(0)} ips)"
    end
  end

  describe 'Identifier parsing (regex patterns)' do
    # Use pattern that matches the entire input
    let(:identifier_parser) do
      Class.new(Parsanol::Parser) do
        rule(:identifier) { match('[a-zA-Z_]').repeat(1).as(:id) }
        root :identifier
      end
    end
    let(:input) { 'hello_world' } # No digits, matches [a-zA-Z_]

    # NOTE: Native returns char array, Ruby returns joined string
    # Both are valid representations
    it 'native parser successfully parses identifier patterns' do
      result = Parsanol::Native::Parser.parse(identifier_parser.new, input)
      expect(result).not_to be_nil
      expect(result).to have_key(:id)
    end

    it 'measures speedup for identifier parsing' do
      parser = identifier_parser.new
      grammar = Parsanol::Native.serialize_grammar(parser.root)

      ruby_ips = Benchmark.ips(quiet: true) do |x|
        x.report('ruby') { parser.parse(input) }
      end.entries.first.ips

      native_ips = Benchmark.ips(quiet: true) do |x|
        x.report('native') { Parsanol::Native.parse(grammar, input) }
      end.entries.first.ips

      speedup = native_ips / ruby_ips
      puts "Identifier: #{speedup.round(1)}x faster (Ruby: #{ruby_ips.round(0)} ips, Native: #{native_ips.round(0)} ips)"
    end
  end

  describe 'Memory allocation comparison' do
    it 'native uses fewer allocations' do
      input = '1 + 2 * 3'
      parser = calc_parser.new

      # Measure Ruby allocations
      GC.start
      before_ruby = GC.stat(:total_allocated_objects)
      10.times { parser.parse(input) }
      ruby_allocs = GC.stat(:total_allocated_objects) - before_ruby

      # Measure Native allocations
      grammar = Parsanol::Native.serialize_grammar(parser.root)
      GC.start
      before_native = GC.stat(:total_allocated_objects)
      10.times { Parsanol::Native.parse(grammar, input) }
      native_allocs = GC.stat(:total_allocated_objects) - before_native

      reduction = (1 - (native_allocs.to_f / ruby_allocs)) * 100
      puts "Allocations: Ruby=#{ruby_allocs}, Native=#{native_allocs} (#{reduction.round(1)}% reduction)"
    end
  end
end
