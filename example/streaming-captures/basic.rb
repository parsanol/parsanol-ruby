# frozen_string_literal: true

# Streaming Parser with Captures Example
#
# Demonstrates how to extract named values from large files without loading
# them into memory. Combines streaming parser efficiency with capture extraction.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'parsanol/parslet'
require 'stringio'

puts 'Streaming Parser with Captures Example'
puts "======================================\n"

# ===========================================================================
# Example 1: Basic Streaming with Captures
# ===========================================================================
puts "--- Example 1: Basic Streaming with Captures ---\n"

# Grammar: Extract email addresses
email_parser = match('[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}').capture(:email)

# Configure streaming with small chunks for demo
config = { chunk_size: 64, window_size: 2 }

input = 'Contact us at user@example.com or support@test.org for help.'

puts "  Input: #{input.inspect}"
puts "  Chunk size: #{config[:chunk_size]}"
puts "  Window size: #{config[:window_size]}"

# NOTE: Requires native extension for full streaming functionality
if defined?(Parsanol::Native) && Parsanol::Native.respond_to?(:is_available) && Parsanol::Native.is_available
  require 'parsanol/streaming_parser'

  streaming_parser = Parsanol::StreamingParser.new(email_parser, **config)

  io = StringIO.new(input)
  results = streaming_parser.parse_stream(io)

  puts "  Results: #{results.length} items parsed"

  results.each do |result|
    puts "    #{result.inspect}"
  end
else
  puts '  (Streaming parser requires native extension)'
  puts '  Falling back to regular parse:'

  result = email_parser.parse(input)
  puts "  Captured email: #{result[:email].inspect}"
end

# ===========================================================================
# Example 2: Log File Analysis
# ===========================================================================
puts "\n--- Example 2: Log File Analysis ---\n"

# Grammar: Parse Apache-style log lines
# Pattern: IP - - [timestamp] "METHOD path ..." status size
ip_parser = match('\d+\.\d+\.\d+\.\d+').capture(:ip)
timestamp_parser = match('[^\]]+').capture(:timestamp)
method_parser = match('[A-Z]+').capture(:method)
path_parser = match('[^\s"]+').capture(:path)

log_parser = ip_parser >> str(' - - [') >> timestamp_parser >> str('] "') >>
             method_parser >> str(' ') >> path_parser >> match('[^"]*') >>
             str('" ') >> match('\d+').capture(:status) >> str(' ') >> match('\d+').capture(:size)

sample_log = <<~LOG
  192.168.1.1 - - [10/Oct/2000:13:55:36 -0700] "GET /index.html HTTP/1.0" 200 2326
  10.0.0.1 - - [10/Oct/2000:13:55:37 -0700] "POST /api/users HTTP/1.0" 201 512
  172.16.0.1 - - [10/Oct/2000:13:55:38 -0700] "GET /favicon.ico HTTP/1.0" 404 128
LOG

puts '  Processing log file...'
puts "  Sample input (#{sample_log.lines.count} lines):"
sample_log.lines.first(2).each { |line| puts "    #{line.strip}" }

if defined?(Parsanol::Native) && Parsanol::Native.respond_to?(:is_available) && Parsanol::Native.is_available
  streaming_parser = Parsanol::StreamingParser.new(log_parser, chunk_size: 128)

  io = StringIO.new(sample_log)
  results = streaming_parser.parse_stream(io)

  puts "  Parsed #{results.length} log lines"
else
  puts '  (Streaming requires native extension)'
  puts '  Parsing first line with regular parser:'

  result = log_parser.parse(sample_log.lines.first)
  puts "    IP: #{result[:ip].inspect}"
  puts "    Method: #{result[:method].inspect}"
  puts "    Status: #{result[:status].inspect}"
end

# ===========================================================================
# Example 3: Memory-Bounded Processing
# ===========================================================================
puts "\n--- Example 3: Memory-Bounded Processing ---\n"

word_parser = match('[a-z]+').capture(:word)
input = 'apple banana cherry date elderberry fig grape'

puts "  Input: #{input}"
puts '  Testing different chunk sizes:'

[16, 32, 64].each do |chunk_size|
  if defined?(Parsanol::Native) && Parsanol::Native.respond_to?(:is_available) && Parsanol::Native.is_available
    streaming_parser = Parsanol::StreamingParser.new(word_parser, chunk_size: chunk_size)
    io = StringIO.new(input)

    results = streaming_parser.parse_stream(io)
    puts "    Chunk size #{chunk_size}: #{results.length} results"
  else
    puts "    Chunk size #{chunk_size}: (requires native extension)"
  end
end

puts "\n  Memory usage is bounded by chunk_size * window_size"

# ===========================================================================
# Example 4: Chunk Size Selection Guide
# ===========================================================================
puts "\n--- Example 4: Chunk Size Selection Guide ---\n"

puts '  | Use Case              | Chunk Size   | Reason |'
puts '  |----------------------|--------------|--------|'
puts '  | Real-time feeds      | 4-16 KB      | Low latency |'
puts '  | Log files            | 256 KB - 1 MB | Throughput |'
puts '  | Network streams      | 8-64 KB      | Balance |'
puts '  | Large files          | 1-4 MB       | Fewer syscalls |'

puts "\n  Window size guidelines:"
puts '  | Grammar type         | Window | Reason |'
puts '  |----------------------|--------|--------|'
puts '  | Sequential           | 1-2    | Minimal backtracking |'
puts '  | Moderate backtracking| 2-3    | Default |'
puts '  | Heavy backtracking   | 4-5    | Complex grammars |'

puts "\n  Memory formula: memory = chunk_size * window_size + capture_state"

# ===========================================================================
# Example 5: StreamingResult Structure
# ===========================================================================
puts "\n--- Example 5: StreamingResult Structure ---\n"

puts '  StreamingParser#parse_stream returns:'
puts '  ['
puts '    {'
puts '      ast: ...,               # Parse tree'
puts '      bytes_processed: N,     # Bytes read'
puts '      captures: { ... },      # Extracted captures'
puts '    },'
puts '    ...'
puts '  ]'

# ===========================================================================
# Summary
# ===========================================================================
puts "\n--- Benefits of Streaming with Captures ---"
puts '* Process files larger than available RAM'
puts '* Captures persist across streaming parse operations'
puts '* Memory bounded by chunk_size * window_size'
puts '* Single pass through data'
puts '* Extract specific fields without loading entire file'

puts "\n--- Performance Notes ---"
puts '* Memory: O(chunk_size * window_size)'
puts '* Captures: Accumulate during parse, available at end'
puts '* For very large captures: process incrementally with reset()'

puts "\n--- API Summary ---"
puts '  parser = StreamingParser.new(grammar, chunk_size: 65536)'
puts '  results = parser.parse_stream(io)'
puts '  results.each { |r| r[:capture_name] }'
