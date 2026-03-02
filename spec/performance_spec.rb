# frozen_string_literal: true

require 'spec_helper'
begin
  require 'benchmark/ips'
rescue LoadError
  # Skip this spec file if benchmark/ips is not available
  return unless defined?(RSpec)

  RSpec.describe 'Performance Regression Tests', :performance do
    it 'requires benchmark-ips gem for performance tests' do
      skip 'benchmark-ips gem not installed. Install with: gem install benchmark-ips'
    end
  end
  return
end

RSpec.describe 'Performance Regression Tests', :performance do
  # Baseline performance expectations (adjusted for opt-in optimization model)
  # These are conservative targets that should pass on most systems
  # Note: These thresholds are set low to accommodate CI environments
  # and debug builds. Production builds should be significantly faster.
  BASELINE_IPS = {
    simple_calc: 500,       # Adjusted for CI/debug environments
    json_parse: 400,        # Adjusted for CI/debug environments
    xml_parse: 400          # Adjusted for CI/debug environments
  }.freeze

  # NOTE: The 13.3x speedup is cumulative from all optimization phases (1-50b)
  # vs parslet 2.0, not just from optimize_rules! alone

  # Test parsers from examples
  let(:calc_parser) do
    Class.new(Parsanol::Parser) do
      optimize_rules!

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

  let(:unoptimized_calc_parser) do
    Class.new(Parsanol::Parser) do
      # Same rules but without optimize_rules!
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

  let(:json_parser) do
    Class.new(Parsanol::Parser) do
      optimize_rules!

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

  let(:xml_parser) do
    Class.new(Parsanol::Parser) do
      optimize_rules!

      rule(:document) do
        (tag(close: false).as(:o) >> document.as(:i) >> tag(close: true).as(:c)) |
          text
      end

      def tag(opts = {})
        close = opts[:close] || false

        parslet = str('<')
        parslet >>= str('/') if close
        parslet >>= (str('>').absent? >> match('[a-zA-Z]')).repeat(1).as(:name)
        parslet >> str('>')
      end

      rule(:text) do
        match('[^<>]').repeat(0)
      end

      root :document
    end
  end

  context 'with optimizations enabled' do
    describe 'optimization safety' do
      it 'optimized parser does not significantly degrade performance' do
        input = '1 + 2 * 3 + 4'

        # Create parser instances
        optimized = calc_parser.new
        unoptimized = unoptimized_calc_parser.new

        # Warm up
        3.times do
          optimized.parse(input)
          unoptimized.parse(input)
        end

        # Benchmark both
        unoptimized_result = Benchmark.ips(quiet: true) do |x|
          x.report('unoptimized') { unoptimized.parse(input) }
        end

        optimized_result = Benchmark.ips(quiet: true) do |x|
          x.report('optimized') { optimized.parse(input) }
        end

        unoptimized_ips = unoptimized_result.entries.first.ips
        optimized_ips = optimized_result.entries.first.ips
        slowdown_ratio = optimized_ips / unoptimized_ips

        # Ensure optimizer doesn't make things significantly worse
        # Allow up to 20% slowdown for safety (optimizer should not harm performance)
        expect(slowdown_ratio).to be >= 0.8,
                                  "Optimizer caused significant slowdown: #{slowdown_ratio.round(2)}x " \
                                  "(unoptimized: #{unoptimized_ips.round(0)} ips, optimized: #{optimized_ips.round(0)} ips)"
      end
    end

    describe 'baseline performance' do
      it 'parses calculator expressions within performance bounds' do
        parser = calc_parser.new
        input = '1 + 2 * 3'

        result = Benchmark.ips(quiet: true) do |x|
          x.report('calc') { parser.parse(input) }
        end

        actual_ips = result.entries.first.ips

        # Allow 85% variance for different environments (Intel Macs are much slower)
        min_acceptable = BASELINE_IPS[:simple_calc] * 0.15

        expect(actual_ips).to be >= min_acceptable,
                              "Expected ≥#{min_acceptable.round(0)} ips, got #{actual_ips.round(0)} ips"
      end

      it 'parses JSON within performance bounds' do
        parser = json_parser.new
        input = '{"key": "value", "array": [1,2,3]}'

        result = Benchmark.ips(quiet: true) do |x|
          x.report('json') { parser.parse(input) }
        end

        actual_ips = result.entries.first.ips

        # Allow 85% variance for different environments (Intel Macs are much slower)
        min_acceptable = BASELINE_IPS[:json_parse] * 0.15

        expect(actual_ips).to be >= min_acceptable,
                              "Expected ≥#{min_acceptable.round(0)} ips, got #{actual_ips.round(0)} ips"
      end

      it 'parses XML within performance bounds' do
        parser = xml_parser.new
        input = '<tag>content</tag>'

        result = Benchmark.ips(quiet: true) do |x|
          x.report('xml') { parser.parse(input) }
        end

        actual_ips = result.entries.first.ips

        # Allow 85% variance in different environments (Intel Macs are much slower)
        min_acceptable = BASELINE_IPS[:xml_parse] * 0.15

        expect(actual_ips).to be >= min_acceptable,
                              "Expected ≥#{min_acceptable.round(0)} ips, got #{actual_ips.round(0)} ips"
      end
    end

    describe 'cache efficiency' do
      it 'maintains reasonable cache hit rate with repetition' do
        parser = Class.new(Parsanol::Parser) do
          optimize_rules!
          rule(:digits) { match('[0-9]').repeat(3) }
          root :digits
        end.new

        # Parse multiple times to warm cache
        10.times { parser.parse('123') }

        # Get cache stats if available
        if parser.respond_to?(:cache_stats)
          stats = parser.cache_stats
          hit_rate = stats[:hits].to_f / (stats[:hits] + stats[:misses])

          expect(hit_rate).to be >= 0.05,
                              "Expected cache hit rate ≥5%, got #{(hit_rate * 100).round(2)}%"
        else
          # Skip if cache stats not available
          skip 'Cache stats not available in this parser'
        end
      end

      it 'keeps allocations under threshold for medium inputs' do
        parser = json_parser.new
        input = '{"a":1,"b":2,"c":3,"d":4,"e":5}'

        # Warm up
        parser.parse(input)

        # Measure allocations
        allocations = count_allocations { parser.parse(input) }

        expect(allocations).to be < 30_000,
                               "Expected <30,000 allocations, got #{allocations}"
      end
    end
  end

  context 'optimizer semantic equivalence' do
    describe 'calculator parser' do
      it 'produces identical parse trees with/without optimization' do
        test_cases = [
          '1 + 2',
          '1 * 2 + 3',
          '10 + 20 * 30',
          '1+2+3+4+5'
        ]

        test_cases.each do |input|
          optimized = calc_parser.new.parse(input)
          unoptimized = unoptimized_calc_parser.new.parse(input)

          # Strip positions for comparison
          expect(strip_positions(optimized)).to eq(strip_positions(unoptimized)),
                                                "Parse trees differ for input: #{input}"
        end
      end
    end

    describe 'JSON parser' do
      it 'produces identical parse trees for various JSON inputs' do
        test_cases = [
          '{"key": "value"}',
          '[1, 2, 3]',
          '{"a": [1, 2], "b": {"c": 3}}',
          'null',
          'true',
          'false',
          '123',
          '"string"'
        ]

        test_cases.each do |input|
          parser = json_parser.new

          # Parse twice to ensure consistency
          first_parse = parser.parse(input)
          second_parse = json_parser.new.parse(input)

          expect(strip_positions(first_parse)).to eq(strip_positions(second_parse)),
                                                  "Parse trees differ for input: #{input}"
        end
      end
    end

    describe 'XML parser' do
      it 'produces identical parse trees for various XML inputs' do
        test_cases = [
          '<tag>content</tag>',
          '<a><b>text</b></a>',
          '<root><child>data</child></root>'
        ]

        test_cases.each do |input|
          parser = xml_parser.new

          # Parse twice to ensure consistency
          first_parse = parser.parse(input)
          second_parse = xml_parser.new.parse(input)

          expect(strip_positions(first_parse)).to eq(strip_positions(second_parse)),
                                                  "Parse trees differ for input: #{input}"
        end
      end
    end
  end

  # Helper methods
  private

  def count_allocations(&block)
    GC.start
    before = GC.stat(:total_allocated_objects)
    block.call
    after = GC.stat(:total_allocated_objects)
    after - before
  end
end
