# CSV Parser - Ruby Implementation (Transform)

## How to Run

```bash
cd parsanol-ruby/example/csv
ruby ruby_transform.rb
```

## Code Walkthrough

### CSV Grammar Definition

The grammar handles rows, fields, and quoted content:

```ruby
rule(:csv) {
  space? >> (row >> (newline >> row).repeat).maybe >> space?
}

rule(:row) {
  (field.as(:f) >> (comma >> field.as(:f)).repeat).as(:row)
}
```

Each row captures multiple fields labeled `:f`, wrapped in `:row`.

### Quoted Field Handling

Quoted fields support escaped quotes:

```ruby
rule(:quoted_field) {
  str('"') >> (
    str('""') | str('"').absent? >> any
  ).repeat.as(:quoted) >> str('"')
}
```

Double quotes (`""`) inside quoted fields represent literal quotes.

### Simple Field Handling

Simple fields exclude commas and newlines:

```ruby
rule(:simple_field) {
  (comma.absent? >> newline.absent? >> any).repeat.as(:simple)
}
```

Negative lookahead prevents field content from including delimiters.

### Field Rule Selection

The field rule tries quoted first:

```ruby
rule(:field) {
  quoted_field | simple_field
}
```

Quoted fields have priority to correctly handle fields starting with `"`.

### Transform Rules

The transform converts parse tree to Ruby arrays:

```ruby
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
```

Pattern matching extracts field content and converts to strings.

### Header-Based Parsing

CSV with headers converts to array of hashes:

```ruby
def parse_csv_with_headers(input)
  rows = parse_csv(input)
  return [] if rows.empty?

  headers = rows.first
  data = rows[1..]

  data.map { |row| headers.zip(row).to_h }
end
```

First row becomes keys; subsequent rows become values.

## Output Types

```ruby
# Without headers:
[["name", "age", "city"], ["Alice", "30", "New York"], ...]

# With headers:
[{"name"=>"Alice", "age"=>"30", "city"=>"New York"}, ...]
```

## Design Decisions

### Why Ruby Transform Over Rust?

Ruby transform allows custom processing logic without modifying Rust code. Useful for domain-specific transformations and data enrichment.

### Why Sequence Pattern for Rows?

`sequence(:fields)` handles both single and multiple fields uniformly, avoiding special cases for one-field rows.

### Why Priority for Quoted Fields?

If simple field were first, `"hello"` would match as simple field `"` followed by errors. Quoted field priority ensures correct parsing.
