# CSV Parser Example - ZeroCopy: Mirrored Objects (Direct FFI)
#
# This example demonstrates ZeroCopy for parsing CSV:
# 1. Rust parser (parsanol-rs) does the parsing
# 2. Rust constructs typed CSV value objects
# 3. Direct Ruby object construction via FFI (no serialization!)
# 4. Maximum performance with zero-copy

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol'

# NOTE: This example requires:
# 1. ZeroCopy extension support for parse_to_objects
# 2. #[derive(RubyObject)] proc macro in Rust
# 3. Matching Ruby class definitions
#
# This serves as an API preview.

# Step 1: Define Ruby classes that mirror Rust struct definitions
module Csv
  class Value
  end

  # Represents a single CSV field
  class Field < Value
    attr_reader :raw, :value

    def initialize(raw:, value:)
      @raw = raw
      @value = value
    end

    def to_s = @value
    def ==(other)
      other.is_a?(Field) && @value == other.value
    end
  end

  # Represents a row of fields
  class Row < Value
    attr_reader :fields

    def initialize(fields)
      @fields = fields
    end

    def [](index)
      @fields[index]
    end

    def size
      @fields.size
    end

    def each(&block)
      @fields.each(&block)
    end

    def to_a
      @fields.map(&:value)
    end

    def to_s
      @fields.map(&:value).join(',')
    end
  end

  # Represents an entire CSV document
  class Document < Value
    attr_reader :rows

    def initialize(rows)
      @rows = rows
    end

    def size
      @rows.size
    end

    def [](index)
      @rows[index]
    end

    def each(&block)
      @rows.each(&block)
    end

    def headers
      @rows.first&.fields&.map(&:value) if @rows.any?
    end

    def data
      @rows[1..] || []
    end

    def to_a
      @rows.map(&:to_a)
    end

    def to_hashes
      return [] unless headers && !data.empty?

      headers = self.headers
      data.map { |row| headers.zip(row.to_a).to_h }
    end
  end
end

# Step 2: Define the parser with output type mapping
class CsvParser < Parsanol::Parser
  # Include ZeroCopy module (planned)
  # include Parsanol::ZeroCopy

  root :csv

  rule(:csv) {
    space? >> (row >> (newline >> row).repeat).maybe >> space?
  }

  rule(:row) {
    (field.as(:f) >> (comma >> field.as(:f)).repeat).as(:row)
  }

  rule(:field) {
    quoted_field | simple_field
  }

  rule(:quoted_field) {
    str('"') >> (
      str('""') | str('"').absent? >> any
    ).repeat.as(:quoted) >> str('"')
  }

  rule(:simple_field) {
    (comma.absent? >> newline.absent? >> any).repeat.as(:simple)
  }

  rule(:comma) { str(',') }
  rule(:newline) { str("\n") | str("\r\n") | str("\r") }
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }

  # Output type mapping (planned feature)
  # output_types(
  #   field: Csv::Field,
  #   row: Csv::Row,
  #   csv: Csv::Document
  # )
end

# Step 3: Parse with direct object construction
def parse_csv(input)
  parser = CsvParser.new

  # ZeroCopy: Parse and get direct Ruby objects
  # NOTE: This requires native extension support
  # doc = parser.parse(input)
  # # doc is already a Csv::Document!
  # # No transform needed, no JSON serialization!

  # For demonstration, simulate what ZeroCopy would return
  doc = simulate_parse(input)
  puts "Parsed: #{doc.class} with #{doc.size} rows"

  doc
end

# Simulated parsing for demonstration
def simulate_parse(input)
  lines = input.strip.split("\n")
  return Csv::Document.new([]) if lines.empty?

  rows = lines.map do |line|
    fields = line.split(',').map do |field|
      raw = field
      # Unescape if quoted
      value = if field.start_with?('"') && field.end_with?('"')
                field[1..-2].gsub('""', '"')
              else
                field.strip
              end
      Csv::Field.new(raw: raw, value: value)
    end
    Csv::Row.new(fields)
  end

  Csv::Document.new(rows)
end

# Example usage
if __FILE__ == $0
  puts "=" * 60
  puts "CSV Parser Example - ZeroCopy: Mirrored Objects"
  puts "=" * 60
  puts
  puts "NOTE: This example shows the planned API for ZeroCopy."
  puts "The native extension support for parse_to_objects is coming soon."
  puts

  simple_csv = <<~CSV
    name,age,city
    Alice,30,New York
    Bob,25,San Francisco
  CSV

  puts "Simple CSV:"
  puts "-" * 40
  doc = parse_csv(simple_csv)

  puts "As arrays:"
  doc.to_a.each { |row| puts row.inspect }

  puts
  puts "Headers: #{doc.headers.inspect}"
  puts "Data rows: #{doc.data.size}"

  puts
  puts "As hashes:"
  doc.to_hashes.each { |row| puts row.inspect }

  # Type-safe access
  puts
  puts "Type-safe access:"
  puts "First row class: #{doc[0].class}"
  puts "First field class: #{doc[0][0].class}"
  puts "First field raw: #{doc[0][0].raw.inspect}"
  puts "First field value: #{doc[0][0].value.inspect}"

  # Custom method example
  puts
  puts "Custom method on Field:"
  field = Csv::Field.new(raw: '"Hello, World"', value: 'Hello, World')
  puts "Field: #{field.value}"

  puts
  puts "=" * 60
  puts "ZeroCopy Benefits for CSV:"
  puts "- FASTEST: No serialization overhead"
  puts "- Type-safe: Each field is a Csv::Field object"
  puts "- Custom methods: Can add validation, formatting, etc."
  puts "- Zero-copy: Direct construction from Rust"
  puts
  puts "When to use ZeroCopy for CSV:"
  puts "- High-throughput CSV processing"
  puts "- When you need typed field access"
  puts "- When you want custom methods on fields/rows"
  puts "- When performance is critical"
  puts "=" * 60
end

# Rust code that would be needed (for reference):
#
# // In parsanol-rs
# use parsanol_ruby_derive::RubyObject;
#
# #[derive(Debug, Clone, RubyObject)]
# #[ruby_class("Csv::Value")]
# pub enum CsvValue {
#     #[ruby_variant("field")]
#     Field {
#         raw: String,
#         value: String,
#     },
#
#     #[ruby_variant("row")]
#     Row(Vec<CsvValue>),
#
#     #[ruby_variant("document")]
#     Document(Vec<CsvValue>),
# }
#
# // The #[derive(RubyObject)] proc macro generates:
# // - Ruby class definitions
# // - to_ruby() implementation
# // - Direct object construction via FFI
