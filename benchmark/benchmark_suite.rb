# frozen_string_literal: true

# Parsanol Ruby Benchmark Suite
#
# Compares parsing performance across:
# - parslet: Original Parslet gem (pure Ruby)
# - parsanol: Parsanol pure Ruby backend
# - parsanol-native: Parsanol with Rust backend
# - parsanol-zerocopy: Parsanol zero-copy mode (fastest)
# - racc: RACC parser generator (compiled)
# - regexp: Pure regex parsing (baseline)
#
# Usage:
#   bundle exec ruby benchmark/benchmark_suite.rb
#   bundle exec ruby benchmark/benchmark_suite.rb --parser json --size medium
#   bundle exec ruby benchmark/benchmark_suite.rb --all

require "bundler/setup"
require "benchmark/ips"
require "optparse"
require "json"
require "fileutils"

class BenchmarkSuite
  PARSERS = %w[parslet parsanol-ruby parsanol-native parsanol-parslet racc
               regexp].freeze
  SIZES = %w[tiny small medium large].freeze
  INPUT_TYPES = %w[json expression express].freeze

  attr_reader :options

  def initialize(args)
    @options = parse_options(args)
    @results = {}
  end

  def parse_options(args)
    opts = {
      parser: nil,        # Specific parser to benchmark
      size: "medium",     # Input size
      input_type: "json", # Type of input
      all: false,         # Run all combinations
      iterations: 10,     # Warmup iterations
      time: 5,            # Benchmark time in seconds
      memory: false,      # Profile memory
      output: "console", # Output format: console, json, html
    }

    OptionParser.new do |parser|
      parser.banner = "Usage: #{$0} [options]"

      parser.on("-p", "--parser NAME", PARSERS,
                "Parser to benchmark (#{PARSERS.join(', ')})") do |p|
        opts[:parser] = p
      end

      parser.on("-s", "--size SIZE", SIZES,
                "Input size (#{SIZES.join(', ')})") do |s|
        opts[:size] = s
      end

      parser.on("-t", "--type TYPE", INPUT_TYPES,
                "Input type (#{INPUT_TYPES.join(', ')})") do |t|
        opts[:input_type] = t
      end

      parser.on("-a", "--all", "Run all combinations") do
        opts[:all] = true
      end

      parser.on("-i", "--iterations N", Integer, "Warmup iterations") do |i|
        opts[:iterations] = i
      end

      parser.on("--time SECONDS", Float, "Benchmark time") do |t|
        opts[:time] = t
      end

      parser.on("-m", "--memory", "Profile memory usage") do
        opts[:memory] = true
      end

      parser.on("-o", "--output FORMAT", %w[console json html],
                "Output format") do |o|
        opts[:output] = o
      end
    end.parse!(args)

    opts
  end

  def run
    puts "=" * 60
    puts "Parsanol Ruby Benchmark Suite"
    puts "=" * 60
    puts "Input type: #{options[:input_type]}"
    puts "Input size: #{options[:size]}"
    puts "Memory profiling: #{options[:memory] ? 'enabled' : 'disabled'}"
    puts

    # Load input
    input = load_input(options[:input_type], options[:size])
    puts "Input size: #{input.bytesize} bytes"
    puts

    # Determine which parsers to test
    parsers_to_test = options[:parser] ? [options[:parser]] : available_parsers

    # Run benchmarks
    results = {}
    parsers_to_test.each do |parser_name|
      puts "Benchmarking #{parser_name}..."
      results[parser_name] = benchmark_parser(parser_name, input)
      puts "  Done: #{results[parser_name][:ips].round(2)} i/s"
    end

    # Print results
    print_results(results)

    # Save results if requested
    save_results(results) if options[:output] != "console"
  end

  private

  def available_parsers
    available = []

    # Check Parslet
    begin
      require "parslet"
      available << "parslet"
    rescue LoadError
      puts "WARNING: parslet not available"
    end

    # Check Parsanol
    begin
      require "parsanol"
      available << "parsanol-ruby"

      if Parsanol::Native.available?
        available << "parsanol-native"
        available << "parsanol-parslet"
      end
    rescue LoadError => e
      puts "WARNING: parsanol not available: #{e.message}"
    end

    # Check RACC
    begin
      require "racc/parser"
      available << "racc"
    rescue LoadError
      puts "WARNING: racc not available"
    end

    # Regexp is always available
    available << "regexp"

    available
  end

  def load_input(type, size)
    filename = File.join(__dir__, "inputs", size, "#{type}.txt")

    if File.exist?(filename)
      File.read(filename)
    else
      generate_input(type, size)
    end
  end

  def generate_input(type, size)
    case type
    when "json"
      generate_json_input(size)
    when "expression"
      generate_expression_input(size)
    when "express"
      generate_express_input(size)
    else
      raise "Unknown input type: #{type}"
    end
  end

  def generate_json_input(size)
    multiplier = { "tiny" => 1, "small" => 10, "medium" => 100,
                   "large" => 1000 }[size] || 1

    objects = Array.new(multiplier) do |i|
      {
        id: i,
        name: "item_#{i}",
        value: rand(1000),
        tags: ["a", "b", "c"].sample(2),
        nested: { x: i * 2, y: i * 3 },
      }
    end

    JSON.generate(items: objects)
  end

  def generate_expression_input(size)
    multiplier = { "tiny" => 1, "small" => 5, "medium" => 20,
                   "large" => 100 }[size] || 1

    expressions = []
    multiplier.times do
      expressions << "#{rand(100)} + #{rand(100)} * #{rand(10)}"
      expressions << "(#{rand(50)} - #{rand(20)}) / #{rand(1..5)}"
      expressions << "#{rand(1000)} * (#{rand(100)} + #{rand(100)})"
    end

    expressions.join("\n")
  end

  def generate_express_input(size)
    entity_count = { "tiny" => 1, "small" => 5, "medium" => 20,
                     "large" => 100 }[size] || 1

    schema = ["SCHEMA test_schema;"]

    entity_count.times do |i|
      schema << ""
      schema << "ENTITY entity_#{i};"
      schema << "  id : INTEGER;"
      schema << "  name : STRING;"
      schema << "  value : REAL;"
      schema << "WHERE"
      schema << "  valid_id : id >= 0;"
      schema << "END_ENTITY;"
    end

    schema << ""
    schema << "END_SCHEMA;"
    schema.join("\n")
  end

  def benchmark_parser(parser_name, input)
    parser = create_parser(parser_name, options[:input_type])

    # Memory profiling
    memory_before = memory_usage if options[:memory]

    # Run benchmark
    result = Benchmark.ips do |x|
      x.config(warmup: options[:iterations], time: options[:time])

      x.report(parser_name) do
        parser.call(input)
      end

      x.compare!
    end

    memory_after = memory_usage if options[:memory]

    # Extract results
    entry = result.entries.first

    {
      ips: entry.iterations_per_second,
      stddev: entry.stddev_percentage,
      cycles: entry.iterations,
      memory_before: memory_before,
      memory_after: memory_after,
      memory_delta: memory_after && memory_before ? memory_after - memory_before : nil,
    }
  end

  def create_parser(parser_name, input_type)
    case parser_name
    when "parslet"
      create_parslet_parser(input_type)
    when "parsanol-ruby"
      create_parsanol_ruby_parser(input_type)
    when "parsanol-native"
      create_parsanol_native_parser(input_type)
    when "parsanol-parslet"
      create_parsanol_parslet_parser(input_type)
    when "racc"
      create_racc_parser(input_type)
    when "regexp"
      create_regexp_parser(input_type)
    else
      raise "Unknown parser: #{parser_name}"
    end
  end

  def create_parslet_parser(input_type)
    require "parslet"

    case input_type
    when "json"
      require_relative "parsers/json_parslet"
      parser = JsonParsletParser.new
      ->(input) { parser.parse(input) }
    when "expression"
      require_relative "parsers/expression_parslet"
      parser = ExpressionParsletParser.new
      ->(input) { parser.parse(input) }
    when "express"
      require_relative "parsers/express_parslet"
      parser = ExpressParsletParser.new
      ->(input) { parser.parse(input) }
    end
  end

  def create_parsanol_ruby_parser(input_type)
    require "parsanol"

    case input_type
    when "json"
      require_relative "parsers/json_parsanol"
      parser = JsonParsanolParser.new
      parser.class.use_ruby_backend!
      ->(input) { parser.parse(input) }
    when "expression"
      require_relative "parsers/expression_parsanol"
      parser = ExpressionParsanolParser.new
      parser.class.use_ruby_backend!
      ->(input) { parser.parse(input) }
    when "express"
      require_relative "parsers/express_parsanol"
      parser = ExpressParsanolParser.new
      parser.class.use_ruby_backend!
      ->(input) { parser.parse(input) }
    end
  end

  def create_parsanol_native_parser(input_type)
    require "parsanol"

    case input_type
    when "json"
      require_relative "parsers/json_parsanol"
      parser = JsonParsanolParser.new
      parser.class.use_rust_backend!
      ->(input) { parser.parse(input) }
    when "expression"
      require_relative "parsers/expression_parsanol"
      parser = ExpressionParsanolParser.new
      parser.class.use_rust_backend!
      ->(input) { parser.parse(input) }
    when "express"
      require_relative "parsers/express_parsanol"
      parser = ExpressParsanolParser.new
      parser.class.use_rust_backend!
      ->(input) { parser.parse(input) }
    end
  end

  def create_parsanol_parslet_parser(input_type)
    require "parsanol/parslet"

    case input_type
    when "json"
      require_relative "parsers/json_parslet_compat"
      parser = JsonParsletCompatParser.new
      ->(input) { parser.parse(input) }
    when "expression"
      require_relative "parsers/expression_parslet_compat"
      parser = ExpressionParsletCompatParser.new
      ->(input) { parser.parse(input) }
    when "express"
      require_relative "parsers/express_parslet_compat"
      parser = ExpressParsletCompatParser.new
      ->(input) { parser.parse(input) }
    end
  end

  def create_racc_parser(input_type)
    # RACC requires pre-compiled parsers
    case input_type
    when "json"
      require_relative "parsers/json_racc"
      parser = JsonRaccParser.new
      ->(input) { parser.parse(input) }
    when "expression"
      require_relative "parsers/expression_racc"
      parser = ExpressionRaccParser.new
      ->(input) { parser.parse(input) }
    else
      # Fallback to simple regex parsing for RACC
      ->(input) { input.scan(/\w+/) }
    end
  end

  def create_regexp_parser(input_type)
    case input_type
    when "json"
      # Simple JSON tokenization
      ->(input) { input.scan(/"[^"]*"|[\[\]{}:,]|\d+|true|false|null/) }
    when "expression"
      # Simple expression tokenization
      ->(input) { input.scan(/\d+|[+\-*\/()]/) }
    when "express"
      # Simple EXPRESS tokenization
      ->(input) { input.scan(/\w+|[;:,]/) }
    end
  end

  def memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i
  rescue StandardError
    nil
  end

  def print_results(results)
    puts
    puts "=" * 60
    puts "RESULTS"
    puts "=" * 60
    puts
    printf "%-25s %12s %10s %12s\n", "Parser", "Iter/s", "Stddev", "vs Fastest"
    puts "-" * 60

    sorted = results.sort_by { |_, r| -r[:ips] }
    fastest = sorted.first.last[:ips]

    sorted.each do |name, result|
      ratio = (result[:ips] / fastest * 100).round(1)
      printf "%-25s %12.2f %9.1f%% %11s\n",
             name, result[:ips], result[:stddev], "#{ratio}%"
    end

    puts
    puts "Fastest: #{sorted.first.first}"
    puts "Slowest: #{sorted.last.first}"
    puts "Speedup: #{(fastest / sorted.last.last[:ips]).round(1)}x"
  end

  def save_results(results)
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    filename = "benchmark_#{timestamp}.json"
    filepath = File.join(__dir__, "reports", filename)

    FileUtils.mkdir_p(File.dirname(filepath))

    data = {
      timestamp: Time.now.iso8601,
      options: options,
      results: results,
    }

    File.write(filepath, JSON.pretty_generate(data))
    puts "\nResults saved to: #{filepath}"
  end
end

if __FILE__ == $0
  suite = BenchmarkSuite.new(ARGV)
  suite.run
end
