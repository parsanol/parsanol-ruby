# frozen_string_literal: true

# Parsanol::StreamingParser - Streaming Parser for Large Inputs
#
# Parse large inputs in chunks without loading the entire input into memory.
# Useful for file parsing, network streams, or very large documents.
#
# Usage:
#   parser = Parsanol::StreamingParser.new(json_grammar)
#
#   File.open("large.json") do |f|
#     parser.parse_stream(f) do |partial_result|
#       # Process each complete element as it's parsed
#       process_item(partial_result)
#     end
#   end
#
# Requires native extension for full functionality.

module Parsanol
  class StreamingParser
    # Default chunk size (4KB)
    DEFAULT_CHUNK_SIZE = 4096

    # Create a new streaming parser
    #
    # @param grammar [Parsanol::Parser, Parsanol::Atoms::Base] Grammar to use
    # @param chunk_size [Integer] Size of chunks to read (default: 4096)
    def initialize(grammar, chunk_size: DEFAULT_CHUNK_SIZE)
      @grammar = grammar
      @chunk_size = chunk_size

      if Parsanol::Native.available?
        grammar_json = Parsanol::Native.serialize_grammar(grammar.root)
        @native_parser = Parsanol::Native.streaming_parser_new(grammar_json)
      else
        @native_parser = nil
      end

      @buffer = String.new
      @position = 0
    end

    # Add a chunk of input
    #
    # @param chunk [String] Input chunk to add
    # @return [Boolean] True if more chunks needed, false if ready for parsing
    def add_chunk(chunk)
      @buffer << chunk

      if @native_parser
        Parsanol::Native.streaming_parser_add_chunk(@native_parser, chunk)
      else
        # Pure Ruby fallback
        false
      end
    end

    # Parse what we have so far
    #
    # @return [Object, nil] Parsed result or nil if need more data
    def parse_chunk
      if @native_parser
        Parsanol::Native.streaming_parser_parse_chunk(@native_parser)
      else
        # Pure Ruby fallback - not supported
        raise NotImplementedError,
          "Streaming parser requires native extension for full functionality."
      end
    end

    # Check if we have enough data to make progress
    #
    # @return [Boolean] True if parser can make progress
    def enough_data?
      if @native_parser
        !Parsanol::Native.streaming_parser_parse_chunk(@native_parser).nil?
      else
        false
      end
    end

    # Parse entire stream (yields partial results)
    #
    # @param io [IO, StringIO] Input source to read from
    # @param chunk_size [Integer] Size of chunks to read
    # @yield [Object] Each complete element as it's parsed
    # @return [Array] All parsed results
    def parse_stream(io, chunk_size: @chunk_size)
      results = []

      loop do
        chunk = io.read(chunk_size)
        break if chunk.nil? || chunk.empty?

        add_chunk(chunk)

        while (result = parse_chunk)
          results << result
          yield result if block_given?
        end
      end

      results
    end

    # Reset the parser for reuse
    def reset
      @buffer = String.new
      @position = 0

      if @native_parser
        grammar_json = Parsanol::Native.serialize_grammar(@grammar.root)
        @native_parser = Parsanol::Native.streaming_parser_new(grammar_json)
      end
    end

    # Get the current buffer
    attr_reader :buffer

    # Get the chunk size
    attr_reader :chunk_size
  end
end
