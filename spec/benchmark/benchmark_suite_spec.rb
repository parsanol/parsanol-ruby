# frozen_string_literal: true

require "spec_helper"
begin
  require_relative "../../benchmark/benchmark_suite"
rescue LoadError
  # Benchmark suite files not available, skip loading this spec
  return
end

describe BenchmarkSuite do
  let(:suite) { described_class.new([]) }

  describe "#parser_supported?" do
    it "supports inline parsers for every input type" do
      %w[json expression express].each do |type|
        expect(suite.send(:parser_supported?, "regexp", type)).to be(true)
      end
    end

    it "supports parsers whose implementation files are checked in" do
      expect(suite.send(:parser_supported?, "parslet", "json")).to be(true)
      expect(suite.send(:parser_supported?, "parsanol-ruby", "json")).to be(true)
      expect(suite.send(:parser_supported?, "parsanol-parslet", "json")).to be(true)
      expect(suite.send(:parser_supported?, "parsanol-ruby", "express")).to be(true)
    end

    it "skips parsers whose implementation files are not checked in" do
      expect do
        expect(suite.send(:parser_supported?, "racc", "json")).to be(false)
      end.to output(/json_racc\.rb is not checked in/).to_stdout
    end

    it "rejects input types a parser has no implementation for" do
      expect(suite.send(:parser_supported?, "racc", "express")).to be(false)
    end

    it "rejects unknown parser names" do
      expect(suite.send(:parser_supported?, "nonexistent", "json")).to be(false)
    end
  end

  describe "#available_parsers" do
    it "includes the pure-Ruby compatibility layer without requiring the native extension" do
      allow(Parsanol::Native).to receive(:available?).and_return(false)

      available = nil
      expect { available = suite.send(:available_parsers) }.to output.to_stdout

      expect(available).to include("parsanol-ruby", "parsanol-parslet", "regexp")
      expect(available).not_to include("parsanol-native")
      expect(available).not_to include("racc")
    end
  end

  describe "#entry_metrics" do
    let(:entry_class) { Struct.new(:ips, :ips_sd, :iterations) }

    it "converts benchmark-ips entries to ips, stddev percentage, and cycles" do
      metrics = suite.send(:entry_metrics, entry_class.new(200.0, 10.0, 1000))

      expect(metrics).to eq(ips: 200.0, stddev: 5.0, cycles: 1000)
    end

    it "reports zero stddev when the entry does not expose ips_sd" do
      bare_entry_class = Struct.new(:ips, :iterations)
      metrics = suite.send(:entry_metrics, bare_entry_class.new(200.0, 1000))

      expect(metrics).to eq(ips: 200.0, stddev: 0, cycles: 1000)
    end

    it "reports zero stddev for zero ips" do
      metrics = suite.send(:entry_metrics, entry_class.new(0.0, 10.0, 0))

      expect(metrics).to eq(ips: 0.0, stddev: 0, cycles: 0)
    end
  end

  describe "#create_racc_parser" do
    it "raises an actionable error for unsupported input types" do
      expect { suite.send(:create_racc_parser, "express") }
        .to raise_error(/racc benchmark does not support input type: express/)
    end
  end

  describe "#create_parser" do
    it "raises for unknown parser names" do
      expect { suite.send(:create_parser, "bogus", "json") }
        .to raise_error(/Unknown parser: bogus/)
    end
  end
end
