# YAML Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/yaml
ruby basic.rb
```

## Code Walkthrough

### Document Structure

A YAML document contains mappings, list items, and comments:

```ruby
rule(:document) { (mapping | list_item | comment | blank_line).repeat(1).as(:document) }
```

YAML is line-oriented with significant indentation.

### Mapping Rule

Key-value pairs with colon separator:

```ruby
rule(:mapping) {
  (key.as(:key) >>
   colon >>
   (inline_value | indented_value)).as(:mapping)
}

rule(:key) {
  (match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat).as(:key)
}
```

Values can be inline (same line) or indented (nested block).

### Inline Value

Scalar on same line as key:

```ruby
rule(:inline_value) {
  (space? >> (string | integer | float | boolean | null).as(:value) >> newline)
}
```

Detects scalar type automatically.

### Indented Value

Nested block with increased indentation:

```ruby
rule(:indented_value) {
  (newline >> indented_block.as(:block))
}

rule(:indented_block) {
  (indent >> (mapping | list_item) >>
   (newline >> indent >> (mapping | list_item)).repeat).as(:block)
}
```

All items at same indent level belong to same block.

### List Item Rule

Hyphen-prefixed values:

```ruby
rule(:list_item) {
  (str('-') >> space >>
   (inline_list_value | indented_value)).as(:list_item)
}
```

List items can contain scalars or nested structures.

### String Rules

Quoted and plain strings:

```ruby
rule(:quoted_string) {
  (str('"') >>
   (str('\\').ignore >> any | str('"').absent? >> any).repeat.as(:string) >>
   str('"')) |
  (str("'") >>
   (str("'").absent? >> any).repeat.as(:string) >>
   str("'"))
}

rule(:plain_string) {
  (newline.absent? >> str(':').absent? >> any).repeat(1).as(:string)
}
```

Quoted strings handle escapes; plain strings don't contain colons.

### Scalar Types

Type detection by pattern:

```ruby
rule(:integer) { (str('+') | str('-')).maybe >> match('[0-9]').repeat(1) }
rule(:float) { ... match('[0-9]').repeat(1) >> str('.') >> match('[0-9]').repeat(1) }
rule(:boolean) { str('true') | str('false') }
rule(:null) { str('null') | str('~') }
```

Order matters: try float before integer to capture decimal point.

## Output Types

```ruby
# Document with mappings
YamlDocument.new([
  YamlMapping.new("name", "Example"),
  YamlMapping.new("database", { "host" => "localhost" })
])

# to_h produces:
{
  "name" => "Example",
  "database" => { "host" => "localhost" }
}
```

## Design Decisions

### Why Inline vs Indented Values?

YAML allows values on same line or nested. Different rules handle the distinct parsing requirements.

### Why Separate String Types?

Quoted strings process escape sequences; plain strings are literal. Different semantics require different rules.

### Why Indentation Tracking?

YAML uses indentation for structure. The parser tracks indent level to correctly nest blocks.

### Why This Subset?

Full YAML is complex (anchors, tags, multiline strings). This subset covers common configuration use cases.
