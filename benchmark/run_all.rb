#!/usr/bin/env ruby
# frozen_string_literal: true

# Parsanol Benchmark Runner
#
# Runs all benchmarks and generates a comprehensive report.
# Users can run this to verify performance claims themselves.
#
# Usage:
#   bundle exec ruby benchmark/run_all.rb
#   bundle exec ruby benchmark/run_all.rb --quick  # Skip large inputs
#   bundle exec ruby benchmark/run_all.rb --parser parslet-ruby  # Only specific parser

require 'bundler/setup'
require 'benchmark/ips'
require 'json'
require 'fileutils'
require 'optparse'
require 'time'

class BenchmarkRunner
  APPROACHES = %w[
    parslet-ruby
    parsanol-ruby
    parsanol-native
    parsanol-ffi-hash
    parsanol-ffi-json
  ].freeze

  SIZES = %w[tiny small medium large].freeze
  INPUT_TYPES = %w[json expression express].freeze

  def initialize(args)
    @options = parse_options(args)
    @results = {}
    @errors = []
  end

  def parse_options(args)
    {
      quick: false,
      parser: nil,
      output_dir: File.join(__dir__, 'reports'),
      verbose: false,
      show_diagram: true
    }.tap do |opts|
      OptionParser.new do |parser|
        parser.banner = "Usage: #{$0} [options]"

        parser.on('-q', '--quick', 'Skip large inputs for faster run') do
          opts[:quick] = true
        end

        parser.on('-p', '--parser NAME', APPROACHES, "Test only this parser") do |p|
          opts[:parser] = p
        end

        parser.on('-v', '--verbose', 'Show detailed output') do
          opts[:verbose] = true
        end

        parser.on('--no-diagram', 'Hide the approaches diagram') do
          opts[:show_diagram] = false
        end

        parser.on('-o', '--output DIR', 'Output directory for reports') do |d|
          opts[:output_dir] = d
        end
      end.parse!(args)
    end
  end

  def run
    print_approaches_diagram if @options[:show_diagram]

    puts "=" * 70
    puts "Parsanol Benchmark Suite - Evidence-Based Performance Verification"
    puts "=" * 70
    puts
    puts "This benchmark suite allows you to verify performance claims yourself."
    puts "All measurements are taken on YOUR machine with YOUR configuration."
    puts
    puts "Started at: #{Time.now}"
    puts

    # Check available parsers
    available = check_available_parsers
    parsers_to_test = @options[:parser] ? [@options[:parser]] : available

    if parsers_to_test.empty?
      puts "ERROR: No parsers available for benchmarking"
      puts "Please install parslet and/or parsanol gems"
      return
    end

    puts "Available parsers: #{available.join(', ')}"
    puts "Testing: #{parsers_to_test.join(', ')}"
    puts

    # Determine sizes to test
    sizes = @options[:quick] ? %w[tiny small medium] : SIZES

    # Run benchmarks
    sizes.each do |size|
      INPUT_TYPES.each do |type|
        run_benchmark_set(parsers_to_test, type, size)
      end
    end

    # Print final report
    print_final_report

    # Save results
    save_results

    puts
    puts "Completed at: #{Time.now}"
    puts
    puts "To see the approaches diagram again:"
    puts "  cat benchmark/APPROACHES.md"
  end

  private

  def print_approaches_diagram
    puts
    puts "╔═════════════════════════════════════════════════════════════════════════════════╗"
    puts "║                    5 APPROACHES FOR JSON PARSING IN RUBY                        ║"
    puts "╚═════════════════════════════════════════════════════════════════════════════════╝"
    puts
    puts "  APPROACH 1: parslet-ruby      → Pure Ruby parsing (baseline)"
    puts "  APPROACH 2: parsanol-ruby     → Parsanol Ruby backend (same speed)"
    puts "  APPROACH 3: parsanol-native   → Rust parsing, AST to Ruby, Ruby JSON"
    puts "  APPROACH 4: parsanol-ffi-hash → Rust parsing, direct Ruby Hash, Ruby JSON"
    puts "  APPROACH 5: parsanol-ffi-json → Rust parsing + JSON serialization (FASTEST)"
    puts
    puts "  See benchmark/APPROACHES.md for detailed diagram"
    puts
    puts "-" * 70
    puts
  end

  def check_available_parsers
    available = []

    # Approach 1: Parslet Ruby
    begin
      require 'parslet'
      available << 'parslet-ruby'
      log "✓ parslet-ruby available (Approach 1: Pure Ruby baseline)"
    rescue LoadError
      log "✗ parslet-ruby not available"
    end

    # Approach 2: Parsanol Ruby backend
    begin
      require 'parsanol'
      available << 'parsanol-ruby'
      log "✓ parsanol-ruby available (Approach 2: Parsanol Ruby backend)"
    rescue LoadError => e
      log "✗ parsanol-ruby not available: #{e.message}"
    end

    # Approach 3: Parsanol Native (Rust → AST → Ruby)
    if available.include?('parsanol-ruby')
      begin
        if defined?(Parsanol::Native) && Parsanol::Native.available?
          available << 'parsanol-native'
          log "✓ parsanol-native available (Approach 3: Rust → AST → Ruby)"
        end
      rescue => e
        log "✗ parsanol-native not available: #{e.message}"
      end
    end

    # Approach 4: Parsanol FFI Hash (Rust → Ruby Hash direct)
    if available.include?('parsanol-native')
      begin
        if Parsanol::Native.respond_to?(:parse_to_objects)
          available << 'parsanol-ffi-hash'
          log "✓ parsanol-ffi-hash available (Approach 4: Rust → Ruby Hash)"
        else
          log "✗ parsanol-ffi-hash not available (parse_to_objects not implemented)"
        end
      rescue => e
        log "✗ parsanol-ffi-hash not available: #{e.message}"
      end
    end

    # Approach 5: Parsanol FFI JSON (Rust → JSON string)
    if available.include?('parsanol-native')
      begin
        if Parsanol::Native.respond_to?(:parse_to_json)
          available << 'parsanol-ffi-json'
          log "✓ parsanol-ffi-json available (Approach 5: Rust → JSON)"
        else
          log "✗ parsanol-ffi-json not available (parse_to_json not implemented)"
        end
      rescue => e
        log "✗ parsanol-ffi-json not available: #{e.message}"
      end
    end

    available
  end

  def run_benchmark_set(parsers, type, size)
    input_file = File.join(__dir__, 'inputs', size, "#{type}.txt")

    unless File.exist?(input_file)
      log "Skipping #{type}/#{size} - input file not found"
      return
    end

    input = File.read(input_file)
    key = "#{type}/#{size}"

    puts
    puts "-" * 70
    puts "Benchmarking: #{key}"
    puts "Input size: #{input.bytesize} bytes"
    puts "-" * 70

    @results[key] = {}

    parsers.each do |parser|
      print "  #{parser.ljust(20)} ... "
      stdout_was = $stdout
      $stdout = StringIO.new if !@options[:verbose]

      begin
        result = benchmark_parser(parser, type, input)
        @results[key][parser] = result
        $stdout = stdout_was
        ips_value = result[:ips]
        stddev_pct = result[:ips] > 0 ? (result[:stddev] / result[:ips] * 100) : 0
        puts "#{ips_value.round(1).to_s.rjust(12)} iter/s  (±#{stddev_pct.round(1)}%)"
      rescue StandardError => e
        $stdout = stdout_was
        puts "ERROR: #{e.message}"
        @errors << { key: key, parser: parser, error: e.message }
      end
    end
  end

  def benchmark_parser(parser_name, type, input)
    parser = create_parser(parser_name, type)

    # Warmup
    warmup_iterations = 5
    warmup_iterations.times { parser.call(input) rescue nil }

    # Benchmark
    result = Benchmark.ips do |x|
      x.config(warmup: 2, time: 3)

      x.report(parser_name) do
        parser.call(input)
      end
    end

    entry = result.entries.first

    {
      ips: entry.ips,
      stddev: entry.respond_to?(:ips_sd) ? entry.ips_sd : 0,
      iterations: entry.iterations
    }
  end

  def create_parser(parser_name, type)
    case parser_name
    when 'parslet-ruby'
      create_parslet_parser(type)
    when 'parsanol-ruby'
      create_parsanol_ruby_parser(type)
    when 'parsanol-native'
      create_parsanol_native_parser(type)
    when 'parsanol-ffi-hash'
      create_parsanol_ffi_hash_parser(type)
    when 'parsanol-ffi-json'
      create_parsanol_ffi_json_parser(type)
    else
      raise "Unknown parser: #{parser_name}"
    end
  end

  def create_parslet_parser(type)
    require 'parslet'

    case type
    when 'json'
      require_relative 'parsers/json_parslet'
      parser = JsonParsletParser.new
      ->(input) { parser.parse(input) }
    when 'expression'
      Class.new(Parslet::Parser) {
        rule(:number) { match('[0-9]').repeat(1) }
        rule(:op) { match('[+\-*/]') }
        rule(:space) { match('\s').repeat(1) }
        rule(:expr) { number >> (space >> op >> space >> number).repeat }
        root(:expr)
      }.new.method(:parse)
    when 'express'
      ->(input) { input.scan(/\w+|[;:,\(\)\[\]]/) }
    end
  end

  def create_parsanol_ruby_parser(type)
    require 'parsanol'

    case type
    when 'json'
      require_relative 'parsers/json_parsanol'
      parser = JsonParsanolParser.new
      ->(input) { parser.parse(input, mode: :ruby) }
    when 'expression'
      Class.new(Parsanol::Parser) {
        rule(:number) { match('[0-9]').repeat(1) }
        rule(:op) { match('[+\-*/]') }
        rule(:space) { match('\s').repeat(1) }
        rule(:expr) { number >> (space >> op >> space >> number).repeat }
        root :expr
      }.new.method(:parse)
    when 'express'
      require_relative 'parsers/express_parsanol'
      parser = ExpressParsanolParser.new
      ->(input) { parser.parse(input, mode: :ruby) }
    end
  end

  def create_parsanol_native_parser(type)
    require 'parsanol'

    case type
    when 'json'
      require_relative 'parsers/json_parsanol'
      parser = JsonParsanolParser.new
      ->(input) { parser.parse(input, mode: :native) }
    when 'expression'
      Class.new(Parsanol::Parser) {
        rule(:number) { match('[0-9]').repeat(1) }
        rule(:op) { match('[+\-*/]') }
        rule(:space) { match('\s').repeat(1) }
        rule(:expr) { number >> (space >> op >> space >> number).repeat }
        root :expr
      }.new.method(:parse)
    when 'express'
      require_relative 'parsers/express_parsanol'
      parser = ExpressParsanolParser.new
      ->(input) { parser.parse(input, mode: :native) }
    end
  end

  def create_parsanol_ffi_hash_parser(type)
    require 'parsanol'

    case type
    when 'json'
      # Approach 4: Rust parses, creates Ruby Hash directly
      # Get the grammar from the parser and serialize it
      require_relative 'parsers/json_parsanol'
      json_parser = JsonParsanolParser.new
      grammar_json = Parsanol::Native.serialize_grammar(json_parser.root)
      ->(input) { Parsanol::Native.parse_to_objects(grammar_json, input) }
    else
      raise "parsanol-ffi-hash not implemented for #{type}"
    end
  end

  def create_parsanol_ffi_json_parser(type)
    require 'parsanol'

    case type
    when 'json'
      # Approach 5: Rust parses and serializes to JSON directly
      require_relative 'parsers/json_parsanol'
      json_parser = JsonParsanolParser.new
      grammar_json = Parsanol::Native.serialize_grammar(json_parser.root)
      ->(input) { Parsanol::Native.parse_to_json(grammar_json, input) }
    else
      raise "parsanol-ffi-json not implemented for #{type}"
    end
  end

  def print_final_report
    puts
    puts "=" * 70
    puts "FINAL RESULTS SUMMARY"
    puts "=" * 70

    # Group by input type
    @results.group_by { |k, _| k.split('/').first }.each do |type, type_results|
      puts
      puts "=== #{type.upcase} ==="
      puts
      printf "%-20s", "Input"
      parsers = type_results.flat_map { |_, v| v.keys }.uniq
      parsers.each { |p| printf "%15s", p[0..12] }
      puts
      puts "-" * (20 + parsers.size * 15)

      type_results.sort_by { |k, _| SIZES.index(k.split('/').last) }.each do |key, results|
        size = key.split('/').last
        printf "%-20s", size

        parsers.each do |parser|
          if results[parser]
            ips = results[parser][:ips]
            printf "%14.1f", ips
          else
            printf "%15s", "N/A"
          end
        end
        puts
      end
    end

    # Speedup summary
    puts
    puts "=" * 70
    puts "SPEEDUP FACTORS (vs parslet-ruby baseline)"
    puts "=" * 70

    @results.each do |key, results|
      next unless results['parslet-ruby']

      results.each do |parser, data|
        next if parser == 'parslet-ruby'
        speedup = data[:ips] / results['parslet-ruby'][:ips]
        puts "#{key}: #{parser} is #{speedup.round(1)}x faster"
      end
    end

    # Errors
    unless @errors.empty?
      puts
      puts "=" * 70
      puts "ERRORS"
      puts "=" * 70
      @errors.each do |err|
        puts "#{err[:key]} / #{err[:parser]}: #{err[:error]}"
      end
    end
  end

  def save_results
    FileUtils.mkdir_p(@options[:output_dir])

    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    filename = "benchmark_#{timestamp}.json"
    filepath = File.join(@options[:output_dir], filename)

    data = {
      timestamp: Time.now.iso8601,
      options: @options,
      system: {
        ruby: RUBY_VERSION,
        platform: RUBY_PLATFORM
      },
      results: @results,
      errors: @errors
    }

    File.write(filepath, JSON.pretty_generate(data))
    puts
    puts "Results saved to: #{filepath}"
    puts
    puts "To compare with future runs, use:"
    puts "  diff #{filepath} benchmark/reports/benchmark_LATEST.json"
  end

  def log(message)
    puts message if @options[:verbose]
  end
end

if __FILE__ == $0
  runner = BenchmarkRunner.new(ARGV)
  runner.run
end
