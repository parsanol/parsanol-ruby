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
  end
end
