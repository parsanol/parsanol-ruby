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

  let(:mode_sensitive_atom_class) do
    Class.new(Parsanol::Atoms::Base) do
      def try(source, _context, consume_all)
        source.consume(1)
        ok(consume_all ? :strict : :prefix)
      end

      def to_s_inner(_prec)
        "MODE"
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

  def consume_all_success_parser_class(interval_cache: false,
                                       adaptive_cache_threshold: 0)
    Class.new(Parsanol::Parser) do
      rule(:a) { str("x") | str("xy") }
      rule(:top) { (a >> str("z")) | a }
      root :top

      define_method(:run_with_context) do |input, reporter, consume_all|
        context = Parsanol::Atoms::Context.new(
          reporter,
          parser_class: self.class,
          adaptive_cache_threshold: adaptive_cache_threshold,
          interval_cache: interval_cache,
        )

        apply(input, context, consume_all)
      end
    end
  end

  def negative_lookahead_parser_class(interval_cache: false)
    Class.new(Parsanol::Parser) do
      rule(:b) { str("q") }
      rule(:neg) { b.absent? }
      rule(:c) { str("qX") }
      rule(:top) { neg | (neg >> c) }
      root :top

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

  def mode_sensitive_parser_class(interval_cache: false)
    atom = mode_sensitive_atom_class.new

    Class.new(Parsanol::Parser) do
      define_method(:a) { atom }
      rule(:top) { (a >> str("z")) | a }
      root :top

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

  def expect_prefix_success_cache_boundary_to_fail(parser_class)
    expect { parser_class.new.parse("xy") }
      .to raise_error(Parsanol::ParseFailed)
  end

  def expect_consume_all_success_boundary_to_parse(parser_class)
    expect(parser_class.new.parse("xy")).to eq("xy")
  end

  def expect_negative_lookahead_boundary_to_fail(parser_class)
    expect { parser_class.new.parse("qX") }
      .to raise_error(Parsanol::ParseFailed)
  end

  def expect_mode_sensitive_boundary_to_parse(parser_class)
    expect(parser_class.new.parse("x")).to eq(:strict)
  end

  describe "adaptive cache threshold" do
    it "keeps the default threshold for atom-level parses" do
      context = described_class.new(nil)

      expect(calls_after_two_attempts(context, "x")).to eq(2)
    end

    it "uses immediate caching for unknown parser classes" do
      parser_class = Class.new(Parsanol::Parser)
      context = described_class.new(nil, parser_class: parser_class)

      expect(calls_after_two_attempts(context, "x")).to eq(1)
    end

    it "keeps named parser thresholds ahead of the parser default" do
      stub_const("JsonParser", Class.new(Parsanol::Parser) do
        rule(:value) { str("x") }
        root(:value)
      end)
      stub_const("JsonParsanolParser", Class.new(Parsanol::Parser) do
        rule(:value) { str("x") }
        root(:value)
      end)

      [JsonParser, JsonParsanolParser].each do |parser_class|
        small_context = described_class.new(nil, parser_class: parser_class)
        large_context = described_class.new(nil, parser_class: parser_class)

        expect(calls_after_two_attempts(small_context, "x" * 9999)).to eq(2)
        expect(calls_after_two_attempts(large_context, "x" * 10_000)).to eq(1)
      end
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

    it "reuses built-in prefix successes for consume-all attempts" do
      expect_prefix_success_cache_boundary_to_fail(
        consume_all_success_parser_class,
      )
    end

    it "reuses built-in prefix successes when adaptive caching is inactive" do
      expect_prefix_success_cache_boundary_to_fail(
        consume_all_success_parser_class(adaptive_cache_threshold: 10_000),
      )
    end

    it "reuses interval-cache prefix successes for consume-all attempts" do
      expect_prefix_success_cache_boundary_to_fail(
        consume_all_success_parser_class(interval_cache: true),
      )
    end

    it "does not reuse consume-all negative lookahead successes for prefix attempts" do
      expect_negative_lookahead_boundary_to_fail(
        negative_lookahead_parser_class,
      )
    end

    it "does not reuse interval-cache negative lookahead successes across modes" do
      expect_negative_lookahead_boundary_to_fail(
        negative_lookahead_parser_class(interval_cache: true),
      )
    end

    it "does not reuse prefix successes for custom consume-all-sensitive atoms" do
      expect_mode_sensitive_boundary_to_parse(
        mode_sensitive_parser_class,
      )
    end

    it "does not reuse interval-cache prefix successes for custom atoms" do
      expect_mode_sensitive_boundary_to_parse(
        mode_sensitive_parser_class(interval_cache: true),
      )
    end
  end
end
