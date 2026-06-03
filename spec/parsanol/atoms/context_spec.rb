# frozen_string_literal: true

require "spec_helper"

describe Parsanol::Atoms::Context do
  let(:cached_atom_class) do
    Class.new(Parsanol::Atoms::Base) do
      attr_reader :calls

      def try(source, _context, _consume_all)
        @calls ||= 0
        @calls += 1
        source.consume(1)
        ok(@calls)
      end
    end
  end

  def calls_after_two_attempts(context, input)
    atom = cached_atom_class.new
    source = Parsanol::Source.new(input)

    context.try_with_cache(atom, source, false)
    source.bytepos = 0
    context.try_with_cache(atom, source, false)

    atom.calls
  end

  def consume_all_cache_parser_class(interval_cache: false)
    Class.new(Parsanol::Parser) do
      rule(:num) { match["0-9"].repeat(1).as(:number) }
      rule(:sequence) { num }
      rule(:iteration) do
        (sequence.as(:sequence) >> iteration.as(:expression)) |
          (sequence >> expression.maybe)
      end
      rule(:expression) do
        iteration |
          ((iteration.as(:dividend) >> str("\\over") >> iteration.as(:divisor)) >> expression.maybe)
      end
      root :expression

      define_method(:run_with_context) do |input, reporter, consume_all|
        context = Parsanol::Atoms::Context.new(
          reporter,
          parser_class: self.class,
          adaptive_cache_threshold: 0,
          interval_cache: interval_cache,
        )

        apply(input, context, consume_all)
      end
    end
  end

  def expect_consume_all_cache_boundary_to_parse(parser_class)
    expect(parser_class.new.parse("1\\over2")).to eq(
      dividend: { number: "1" },
      divisor: { number: "2" },
    )
  end

  describe "adaptive cache threshold" do
    it "keeps the default threshold for atom-level parses" do
      context = described_class.new(nil)

      expect(calls_after_two_attempts(context, "x")).to eq(2)
    end

    it "uses immediate caching for parser classes by default" do
      parser_class = Class.new(Parsanol::Parser)
      context = described_class.new(nil, parser_class: parser_class)

      expect(calls_after_two_attempts(context, "x")).to eq(1)
    end

    it "keeps named parser thresholds ahead of the parser default" do
      stub_const("JsonParser", Class.new(Parsanol::Parser) do
        rule(:value) { str("x") }
        root(:value)
      end)

      small_context = described_class.new(nil, parser_class: JsonParser)
      large_context = described_class.new(nil, parser_class: JsonParser)

      expect(calls_after_two_attempts(small_context, "x" * 9999)).to eq(2)
      expect(calls_after_two_attempts(large_context, "x" * 10_000)).to eq(1)
    end

    it "does not reuse consume-all failures for prefix attempts at the same position" do
      expect_consume_all_cache_boundary_to_parse(
        consume_all_cache_parser_class,
      )
    end

    it "does not reuse consume-all failures for interval-cache prefix attempts" do
      expect_consume_all_cache_boundary_to_parse(
        consume_all_cache_parser_class(interval_cache: true),
      )
    end
  end
end
