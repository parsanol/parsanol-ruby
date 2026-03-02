# CSV Parser Example - Ruby Transform: Ruby Transform (Parslet-Compatible)
#
# This example demonstrates Ruby Transform for parsing CSV:
# 1. Rust parser (parsanol-rs) does the fast parsing
# 2. Returns a generic tree (hash/array/string structure)
# 3. Ruby transform converts tree to Ruby objects

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol'

# Step 1: Define the CSV parser grammar
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

  # Quoted field: "value with ""escaped"" quotes"
  rule(:quoted_field) {
    str('"') >> (
      str('""') | str('"').absent? >> any
    ).repeat.as(:quoted) >> str('"')
  }

  # Simple field: value without commas or quotes
  rule(:simple_field) {
    (comma.absent? >> newline.absent? >> any).repeat.as(:simple)
  }

  # Helpers
  rule(:comma) { str(',') }
  rule(:newline) { str("\n") | str("\r\n") | str("\r") }
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }
end

# Step 2: Define the transform (Parslet-style)
class CsvTransform < Parsanol::Transform
  # Transform a row (sequence of fields)
  rule(row: sequence(:fields)) {
    fields.map { |f| f.is_a?(Hash) ? unescape(f) : f }
  }

  # Transform quoted field
  rule(quoted: simple(:q)) {
    q.to_s.gsub('""', '"')
  }

  # Transform simple field
  rule(simple: simple(:s)) {
    s.to_s.strip
  }
end

# Step 3: Parse and transform
def parse_csv(input)
  parser = CsvParser.new
  transform = CsvTransform.new

  # Ruby Transform: Parse in Rust, transform in Ruby
  tree = parser.parse(input)
  puts "Parse tree: #{tree.inspect[0..200]}..."

  result = transform.apply(tree)
  puts "Result: #{result.inspect[0..200]}..."

  result
end

# Step 4: Convert to array of hashes (for CSV with headers)
def parse_csv_with_headers(input)
  rows = parse_csv(input)

  return [] if rows.empty?

  # First row is headers
  headers = rows.first
  data = rows[1..]

  data.map { |row| headers.zip(row).to_h }
end

# Example usage
if __FILE__ == $0
  puts "=" * 60
  puts "CSV Parser Example - Ruby Transform: Ruby Transform"
  puts "=" * 60

  # Simple CSV
  simple_csv = <<~CSV
    name,age,city
    Alice,30,New York
    Bob,25,San Francisco
  CSV

  puts
  puts "Simple CSV:"
  puts "-" * 40
  result = parse_csv(simple_csv)
  puts result.inspect

  # CSV with headers parsed to hashes
  puts
  puts "CSV with headers:"
  puts "-" * 40
  result = parse_csv_with_headers(simple_csv)
  result.each { |row| puts row.inspect }

  # CSV with quoted fields
  quoted_csv = <<~CSV
    name,description,city
    Alice,"Hello, World",New York
    Bob,"Test ""quoted"" text",Boston
  CSV

  puts
  puts "CSV with quoted fields:"
  puts "-" * 40
  result = parse_csv_with_headers(quoted_csv)
  result.each { |row| puts row.inspect }

  # Empty CSV
  empty_csv = ""

  puts
  puts "Empty CSV:"
  puts "-" * 40
  result = parse_csv(empty_csv)
  puts result.inspect

  puts
  puts "=" * 60
  puts "Ruby Transform Benefits for CSV:"
  puts "- Flexible transform logic"
  puts "- Easy to add custom processing"
  puts "- Compatible with existing Parslet code"
  puts "=" * 60
end
