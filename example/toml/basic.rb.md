# TOML Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/toml
ruby basic.rb
```

## Code Walkthrough

### Document Structure

A TOML document contains entries in sequence:

```ruby
rule(:document) { (comment | table | key_value | newline).repeat.as(:document) }
```

Order matters: comments and tables appear where they are in the source.

### Comment Rule

Hash-prefixed comments to end of line:

```ruby
rule(:comment) {
  (str('#') >> (newline.absent? >> any).repeat).as(:comment) >> newline
}
```

Comments are captured but typically ignored in output.

### Table Rule

Square-bracketed section headers:

```ruby
rule(:table) {
  (str('[') >>
   table_name.as(:name) >>
   str(']') >>
   newline).as(:table)
}

rule(:table_name) {
  (match('[a-zA-Z0-9_]') | str('.') | str('-')).repeat(1)
}
```

Dotted names like `[database.server]` create nested tables.

### Key-Value Rule

Assignment with various value types:

```ruby
rule(:key_value) {
  (key.as(:key) >>
   space? >>
   str('=') >>
   space? >>
   value.as(:value) >>
   newline).as(:key_value)
}
```

Keys are alphanumeric with underscores.

### String Rules

Basic strings with escapes and literal strings:

```ruby
rule(:basic_string) {
  (str('"') >>
   (str('\\').ignore >> any | str('"').absent? >> any).repeat.as(:string) >>
   str('"')).as(:basic_string)
}

rule(:literal_string) {
  (str("'") >>
   (str("'").absent? >> any).repeat.as(:string) >>
   str("'")).as(:literal_string)
}
```

Basic strings process escapes; literal strings don't.

### Numeric Rules

Integers and floating-point numbers:

```ruby
rule(:integer) {
  (str('+') | str('-')).maybe >>
  match('[0-9]').repeat(1).as(:integer)
}

rule(:float) {
  ((str('+') | str('-')).maybe >>
   match('[0-9]').repeat(1) >>
   str('.') >>
   match('[0-9]').repeat(1) >>
   (match('[eE]') >> ...).maybe).as(:float)
}
```

Scientific notation is supported for floats.

### Array Rule

Square-bracketed value lists:

```ruby
rule(:array) {
  (str('[') >>
   space? >>
   (value >> (comma >> value).repeat).maybe.as(:elements) >>
   space? >>
   str(']')).as(:array)
}
```

Arrays can contain any value type, mixed.

### Inline Table Rule

Curly-braced key-value pairs:

```ruby
rule(:inline_table) {
  (str('{') >>
   space? >>
   (key_value_inline >> (comma >> key_value_inline).repeat).maybe.as(:pairs) >>
   space? >>
   str('}')).as(:inline_table)
}
```

Inline tables are compact single-line objects.

## Output Types

```ruby
# Document with entries
TomlDocument.new([
  TomlComment.new(" comment"),
  TomlKeyValue.new("title", "TOML Example"),
  TomlTable.new("database"),
  TomlKeyValue.new("host", "localhost")
])

# to_h produces:
{
  "title" => "TOML Example",
  "database" => { "host" => "localhost" }
}
```

## Design Decisions

### Why Track Current Table in to_h?

TOML key-value pairs belong to the most recent table. The transformation tracks this context.

### Why Two String Types?

TOML specification defines basic strings (with escapes) and literal strings (raw). Different rules handle them correctly.

### Why Separate Integer and Float?

Type distinction matters for configuration values. Separate rules preserve type information.
