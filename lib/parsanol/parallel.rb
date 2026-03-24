# frozen_string_literal: true

module Parsanol
  # Parallel parsing support for batch processing multiple inputs.
  # Uses rayon for linear speedup on multi-core systems.
  #
  # @example Parse multiple files in parallel
  #   grammar = MyParser.new.serialize_grammar
  #   inputs = Dir.glob("*.json").map { |f| File.read(f) }
  #
  #   results = Parsanol::Parallel.parse_batch(grammar, inputs)
  #   results.each_with_index do |result, i|
  #     case result
  #     when Hash then puts "File #{i} parsed: #{result}"
  #     when Parsanol::ParseFailed then puts "File #{i} failed: #{result.message}"
  #     end
  #   end
  #
  module Parallel
    # Configuration for parallel parsing.
    #
    # @example Configure with 8 threads
    #   config = Parsanol::Parallel::Config.new
    #     .with_num_threads(8)
    #     .with_min_chunk_size(50)
    #
    #   results = Parsanol::Parallel.parse_batch(grammar, inputs, config: config)
    #
    class Config
      # @return [Integer, nil] Number of threads (nil = auto-detect based on CPU cores)
      attr_accessor :num_threads

      # @return [Integer] Minimum inputs per thread (default: 10)
      attr_accessor :min_chunk_size

      def initialize
        @num_threads = nil # Auto-detect
        @min_chunk_size = 10
      end

      # Set the number of threads to use.
      #
      # @param n [Integer] Number of threads
      # @return [Config] self for chaining
      def with_num_threads(n)
        @num_threads = n
        self
      end

      # Set the minimum chunk size per thread.
      #
      # @param size [Integer] Minimum inputs per thread
      # @return [Config] self for chaining
      def with_min_chunk_size(size)
        @min_chunk_size = size
        self
      end
    end

    class << self
      # Parse multiple inputs in parallel.
      #
      # When the native extension with parallel feature is available,
      # this uses rayon for parallel execution. Otherwise, falls back
      # to sequential parsing.
      #
      # @param grammar_json [String] JSON-serialized grammar
      # @param inputs [Array<String>] Array of input strings to parse
      # @param config [Config] Parallel configuration (optional)
      # @return [Array<Object>] Array of parse results in same order as inputs
      #
      # @example Basic usage
      #   results = Parsanol::Parallel.parse_batch(grammar, inputs)
      #
      # @example With configuration
      #   config = Parsanol::Parallel::Config.new.with_num_threads(4)
      #   results = Parsanol::Parallel.parse_batch(grammar, inputs, config: config)
      #
      def parse_batch(grammar_json, inputs, config: Config.new)
        unless Parsanol::Native.available?
          raise LoadError,
                "Parallel parsing requires native extension. " \
                "Run `rake compile` to build the extension."
        end

        Parsanol::Native.parse_batch_parallel(
          grammar_json,
          inputs,
          num_threads: config.num_threads
        )
      end

      # Parse multiple inputs in parallel with transformation.
      #
      # @param grammar_json [String] JSON-serialized grammar
      # @param inputs [Array<String>] Array of input strings to parse
      # @param transform [Parsanol::Transform] Transform to apply to each result
      # @param config [Config] Parallel configuration (optional)
      # @return [Array<Object>] Array of transformed results
      #
      def parse_batch_with_transform(grammar_json, inputs, transform, config: Config.new)
        results = parse_batch(grammar_json, inputs, config: config)
        results.map { |result| transform.apply(result) }
      end

      # Get the number of available CPU cores for parallel processing.
      #
      # @return [Integer] Number of available cores
      def available_cores
        require 'etc'
        Etc.nprocessors
      rescue StandardError
        1
      end

      # Estimate optimal number of threads for a given input size.
      #
      # @param input_count [Integer] Number of inputs to process
      # @return [Integer] Recommended number of threads
      def optimal_threads(input_count)
        cores = available_cores
        # Don't use more threads than inputs
        [cores, input_count].min
      end
    end
  end
end
