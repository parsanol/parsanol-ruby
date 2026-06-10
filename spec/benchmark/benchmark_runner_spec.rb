# frozen_string_literal: true

require "spec_helper"
require_relative "../../benchmark/run_all"

describe BenchmarkRunner do
  describe "#check_available_parsers" do
    it "includes cache-threshold parsers when the input type is selected" do
      runner = described_class.new(
        ["--type", "cache_threshold", "--no-diagram"],
      )

      expect(runner.send(:check_available_parsers))
        .to include("parsanol-cache-default", "parsanol-cache-1000")
    end

    BenchmarkRunner::CACHE_THRESHOLD_APPROACHES.each do |parser|
      it "includes cache-threshold parsers when #{parser} is selected directly" do
        runner = described_class.new(["--parser", parser, "--no-diagram"])

        expect(runner.send(:selected_input_types)).to eq(["cache_threshold"])
        expect(runner.send(:check_available_parsers))
          .to include("parsanol-cache-default", "parsanol-cache-1000")
      end
    end
  end

  describe "#parsers_for_type" do
    let(:runner) { described_class.new(["--no-diagram"]) }

    it "uses only cache parsers for cache-threshold inputs" do
      parsers = [
        "parslet-ruby",
        "parsanol-ruby",
        "parsanol-cache-default",
        "parsanol-cache-1000",
      ]

      expect(runner.send(:parsers_for_type, parsers, "cache_threshold"))
        .to eq(["parsanol-cache-default", "parsanol-cache-1000"])
    end

    it "excludes cache parsers from normal inputs" do
      parsers = [
        "parslet-ruby",
        "parsanol-ruby",
        "parsanol-cache-default",
        "parsanol-cache-1000",
      ]

      expect(runner.send(:parsers_for_type, parsers, "json"))
        .to eq(["parslet-ruby", "parsanol-ruby"])
    end
  end

  describe "#compatible_parsers_for" do
    let(:runner) { described_class.new(["--no-diagram"]) }

    it "returns compatible parsers for selected input types" do
      parsers = ["parslet-ruby", "parsanol-cache-default"]

      expect(runner.send(:compatible_parsers_for, parsers, ["cache_threshold"]))
        .to eq(["parsanol-cache-default"])
    end

    it "returns an empty list for incompatible parser/type selections" do
      parsers = ["parslet-ruby"]

      expect(runner.send(:compatible_parsers_for, parsers, ["cache_threshold"]))
        .to eq([])
    end
  end
end
