# Streaming Parser with Captures - Ruby Implementation

## How to Run

```bash
ruby example/streaming-captures/basic.rb
```

## Requirements

Streaming parsing requires the native extension:

```ruby
# Check if native extension is available
Parsanol::Native.available?  # => true/false
```

## Code Walkthrough

### Basic Setup

```ruby
require 'parsanol/streaming_parser'

parser = Parsanol::StreamingParser.new(grammar, chunk_size: 65536)

File.open("large.log") do |f|
  parser.parse_stream(f) do |result|
    # Process each result
    puts result[:capture_name]
  end
end
```

### Chunk Configuration

```ruby
parser = Parsanol::StreamingParser.new(
  grammar,
  chunk_size: 64 * 1024,  # 64 KB chunks
  window_size: 2           # Keep 2 chunks in memory
)
```

### Accessing Captures

```ruby
results = parser.parse_stream(io)

results.each do |result|
  result[:capture_name]  # Access captured value
end
```

## StreamingParser API

```ruby
class Parsanol::StreamingParser
  # Create new streaming parser
  def initialize(grammar, chunk_size: 4096)

  # Add a chunk of input
  def add_chunk(chunk)

  # Parse current buffer
  def parse_chunk

  # Parse entire stream (returns array of results)
  def parse_stream(io, chunk_size: @chunk_size)

  # Reset for reuse
  def reset
end
```

## Chunk Size Selection

| Use Case | Chunk Size | Reason |
|----------|------------|--------|
| Real-time feeds | 4-16 KB | Low latency |
| Log files | 256 KB - 1 MB | Throughput |
| Network streams | 8-64 KB | Balance |
| Large files | 1-4 MB | Fewer syscalls |

## Memory Bounds

Memory is bounded by:
```
memory = chunk_size * window_size + capture_state
```

For example:
- chunk_size: 64KB
- window_size: 2
- Base memory: 128KB + captures

## Performance Notes

| Metric | Value |
|--------|-------|
| Memory overhead | chunk_size * window_size |
| Streaming overhead | ~10% vs non-streaming |
| Native required | Yes for full functionality |

**Optimization Tips**:
1. Use appropriate chunk size for your use case
2. Process results incrementally
3. Reset parser between independent inputs
4. Use scopes to limit capture accumulation

## Error Handling

```ruby
begin
  results = parser.parse_stream(io)
rescue Parsanol::ParseFailed => e
  puts "Parse error: #{e}"
end
```

## StreamingResult Structure

Each result from `parse_stream` contains:

```ruby
{
  ast: ...,               # Parse tree
  bytes_processed: N,     # Bytes read
  captures: { ... },      # Extracted captures
}
```

## Example: Log File Processing

```ruby
# Parse Apache access logs
log_grammar = ip.capture(:ip) >> str(' - - [') >>
              timestamp.capture(:ts) >> str('] "') >>
              method.capture(:method) >> str(' ') >>
              path.capture(:path) >> match('[^"]*') >> str('" ') >>
              status.capture(:status) >> str(' ') >>
              size.capture(:size)

parser = Parsanol::StreamingParser.new(log_grammar, chunk_size: 64 * 1024)

File.open("access.log") do |f|
  parser.parse_stream(f).each do |result|
    puts "#{result[:ip]} - #{result[:method]} #{result[:path]} - #{result[:status]}"
  end
end
```

## Backend Compatibility

| Backend | Support | Notes |
|---------|---------|-------|
| Packrat | N/A | Use streaming instead |
| Bytecode | N/A | Use streaming instead |
| Streaming | Full | Primary backend for this feature |

## Design Decisions

### Why Chunk-Based?

Chunk-based streaming provides:
- Predictable memory usage
- Efficient I/O patterns
- Natural boundaries for backtracking

### Capture Persistence

Captures accumulate during the parse and are available in the final result:

```ruby
# Captures from entire stream
results = parser.parse_stream(io)
results.flat_map { |r| r.keys }.uniq  # All capture names
```

### Memory Management

The streaming parser automatically:
- Manages chunk buffers
- Handles chunk boundaries
- Preserves capture state across chunks

## Related Examples

- `example/captures/` - Basic capture atom usage
- `example/scopes/` - Limiting capture scope
- `example/dynamic/` - Context-sensitive parsing
