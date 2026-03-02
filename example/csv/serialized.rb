# CSV Parser Example - Serialized: JSON Serialization
#
# This example demonstrates Serialized for parsing CSV:
# 1. Rust parser (parsanol-rs) does the parsing
# 2. Rust transform converts to typed structs
# 3. Result is serialized to JSON
# 4. Ruby deserializes JSON to Ruby objects
#
# This option is useful when you need to validate/proces CSV
# and get structured output for other tools.

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol'
require 'json'

# NOTE: This example requires the native extension to support parse_to_json
# which is planned but not yet implemented. This serves as an API preview.

# Step 1: Define the CSV parser grammar (same as Option A)
class CsvParser < Parsanol::Parser
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
end

# Step 2: Define typed classes for CSV data
class CsvRow
  attr_reader :fields

  def initialize(fields)
    @fields = fields
  end

  def to_a = @fields

  def [](index)
    @fields[index]
  end

  def each(&block)
    @fields.each(&block)
  end
end

class CsvDocument
  attr_reader :rows

  def initialize(rows)
    @rows = rows
  end

  def to_a
    @rows.map(&:to_a)
  end

  def headers
    @rows.first&.fields
  end

  def data
    @rows[1..] || []
  end

  def to_hashes
    return [] unless headers && !data.empty?

    headers = self.headers
    data.map { |row| headers.zip(row.fields).to_h }
  end
end

# Step 3: Deserializer
class CsvDeserializer
  def self.from_json(json_string)
    data = JSON.parse(json_string)

    case data
    when Array
      rows = data.map { |row_data| CsvRow.new(row_data) }
      CsvDocument.new(rows)
    else
      raise "Expected array of rows, got #{data.class}"
    end
  end
end

# Step 4: Parse with JSON output
def parse_csv(input)
  parser = CsvParser.new

  # Serialized: Parse and get JSON from Rust
  # NOTE: This requires native extension support
  # output_json = parser.parse_to_json(input)

  # For now, simulate by using Option A then serializing
  require_relative 'csv_option_a'
  tree = parser.parse(input)
  transform = CsvTransform.new
  result = transform.apply(tree)

  # This would come from Rust in Serialized
  # Convert to array format for JSON
  output_json = result.to_json
  puts "Output JSON (first 200 chars): #{output_json[0..200]}..."

  # Deserialize to typed objects
  csv_doc = CsvDeserializer.from_json(output_json)
  puts "Parsed: #{csv_doc.class} with #{csv_doc.rows.size} rows"

  csv_doc
end

# Transform class (needed for simulation)
class CsvTransform < Parsanol::Transform
  rule(row: sequence(:fields)) {
    fields.map { |f| f.is_a?(Hash) ? unescape(f) : f }
  }

  rule(quoted: simple(:q)) { unescape_quoted(q.to_s) }
  rule(simple: simple(:s)) { s.to_s.strip }

  private

  def unescape(field)
    if field.is_a?(Hash) && field[:quoted]
      unescape_quoted(field[:quoted])
    elsif field.is_a?(Hash) && field[:simple]
      field[:simple].to_s.strip
    else
      field
    end
  end

  def unescape_quoted(str)
    str.gsub('""', '"')
  end
end

# Example usage
if __FILE__ == $0
  puts "=" * 60
  puts "CSV Parser Example - Serialized: JSON Serialization"
  puts "=" * 60
  puts
  puts "NOTE: This example shows the planned API for Serialized."
  puts "The native extension support for parse_to_json is coming soon."
  puts

  simple_csv = <<~CSV
    name,age,city
    Alice,30,New York
    Bob,25,San Francisco
  CSV

  puts "Simple CSV:"
  puts "-" * 40
  csv_doc = parse_csv(simple_csv)

  puts
  puts "As arrays:"
  csv_doc.to_a.each { |row| puts row.inspect }

  puts
  puts "As hashes:"
  csv_doc.to_hashes.each { |row| puts row.inspect }

  puts
  puts "=" * 60
  puts "Serialized Benefits for CSV:"
  puts "- Structured JSON output for other tools"
  puts "- Easy to cache/store results"
  puts "- Type-safe access via CsvRow/CsvDocument classes"
  puts "- Cross-language compatibility"
  puts "=" * 60
end
