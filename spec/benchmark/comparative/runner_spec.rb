# frozen_string_literal: true

require 'spec_helper'
begin
  require_relative '../../../benchmark/comparative/parser_suite'
  require_relative '../../../benchmark/comparative/test_inputs'
  require_relative '../../../benchmark/comparative/metrics_collector'
  require_relative '../../../benchmark/comparative/runner'
  require_relative '../../../benchmark/comparative/parsers/json_parser'
rescue LoadError
  # Benchmark suite files not available, skip loading this spec
  return
end

RSpec.describe Parsanol::Comparative::BenchmarkRunner do
  # Use faster config for tests
  before do
    # Reduce benchmark time for tests
    allow_any_instance_of(Parsanol::Comparative::MetricsCollector)
      .to receive(:collect_timing).and_wrap_original do |_method, *args|
        # Use only 2 samples in tests for speed
        parser, input = args
        samples = []

        2.times do
          iterations = 0
          elapsed = Benchmark.realtime do
            10.times do # Reduced from 100
              parser.parse(input)
              iterations += 1
            end
          end
          samples << (iterations / elapsed)
        end

        mean_ips = samples.sum / samples.size
        {
          ips: mean_ips,
          stddev_percent: 5.0,
          microseconds_per_iteration: 1_000_000.0 / mean_ips,
          samples: samples.size
        }
      end
  end

  describe '#run_comparative_benchmarks' do
    it 'executes benchmarks for all registered parsers' do
      runner = described_class.new
      results = runner.run_comparative_benchmarks

      expect(results).to be_a(Hash)
      expect(results[:json_parser]).not_to be_nil
      expect(results[:json_parser]).not_to be_empty
    end

    it 'collects timing metrics' do
      runner = described_class.new
      results = runner.run_comparative_benchmarks

      json_results = results[:json_parser][:simple_object]
      expect(json_results[:timing]).to have_key(:ips)
      expect(json_results[:timing][:ips]).to be > 0
    end

    it 'collects memory metrics' do
      runner = described_class.new
      results = runner.run_comparative_benchmarks

      json_results = results[:json_parser][:simple_object]
      expect(json_results[:memory]).to have_key(:objects_allocated)
      expect(json_results[:memory][:objects_allocated]).to be > 0
    end

    it 'benchmarks all test cases for each parser' do
      runner = described_class.new
      results = runner.run_comparative_benchmarks

      json_results = results[:json_parser]
      expect(json_results).to have_key(:simple_object)
      expect(json_results).to have_key(:simple_array)
      expect(json_results).to have_key(:nested_object)
      expect(json_results).to have_key(:mixed_array)
      expect(json_results).to have_key(:large_object)
    end
  end

  describe '#initialize' do
    it 'initializes with registered parsers' do
      runner = described_class.new
      expect(runner.parsers).to be_a(Hash)
      expect(runner.parsers).to have_key(:json_parser)
    end

    it 'initializes with test inputs' do
      runner = described_class.new
      expect(runner.inputs).to be_a(Hash)
      expect(runner.inputs).to have_key(:json_parser)
    end

    it 'initializes metrics collector' do
      runner = described_class.new
      expect(runner.metrics).to be_a(Parsanol::Comparative::MetricsCollector)
    end
  end
end
