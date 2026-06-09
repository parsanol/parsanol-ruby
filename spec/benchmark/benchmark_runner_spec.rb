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
end
