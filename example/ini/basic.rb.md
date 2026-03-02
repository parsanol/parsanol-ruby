# INI Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/ini
ruby basic.rb
```

## Code Walkthrough

### Section Header Rule

Sections are enclosed in square brackets:

```ruby
rule(:section) {
  (space? >> str('[') >> section_name.as(:name) >> str(']') >> space? >> str("\n").maybe).as(:section)
}

rule(:section_name) {
  (match('[^]\n]').repeat(1))
}
```

Section names exclude brackets and newlines for valid syntax.

### Key-Value Pair Rule

Configuration entries follow `key = value` format:

```ruby
rule(:key_value) {
  (space? >> key.as(:key) >> space? >> str('=') >> space? >> value.as(:value) >> space? >> str("\n").maybe).as(:kv)
}

rule(:key) {
  match('[^\s=]').repeat(1)
}

rule(:value) {
  (match('[^\n]').repeat)
}
```

Keys cannot contain whitespace or equals; values extend to end of line.

### Comment Rule

Comments start with `#` or `;`:

```ruby
rule(:comment) {
  (space? >> (str('#') | str(';')) >> match('[^\n]').repeat >> str("\n").maybe).as(:comment)
}
```

Both comment styles are common in INI files.

### Top-Level Grammar

The INI file is a sequence of sections, key-value pairs, and comments:

```ruby
rule(:ini) {
  (section | key_value | comment).repeat
}
```

Key-value pairs before any section header belong to no section.

### IniFile Helper Class

A helper class manages parsed data:

```ruby
class IniFile
  attr_reader :sections

  def initialize
    @sections = {}
    @current_section = nil
  end

  def set_section(name)
    @current_section = name
    @sections[name] ||= {}
  end

  def set_key_value(key, value)
    section = @sections[@current_section] || {}
    section[key.to_s.strip] = value.to_s.strip
    @sections[@current_section] = section
  end
end
```

Track current section and build nested hash structure.

## Output Types

```ruby
# Parse tree:
[
  {:section=>{:name=>"database"@s}},
  {:kv=>{:key=>"host"@s, :value=>"localhost"@s}},
  {:kv=>{:key=>"port"@s, :value=>"5432"@s}}
]

# After processing:
{
  "database" => {"host"=>"localhost", "port"=>"5432"},
  "server" => {"host"=>"0.0.0.0", "port"=>"8080", "debug"=>"true"}
}
```

## Design Decisions

### Why Track Current Section in Helper Class?

INI files are inherently sectioned; the helper maintains context as we iterate through parse results.

### Why Allow Both Comment Prefixes?

`#` is Unix-style, `;` is Windows-style. Supporting both maximizes compatibility.

### Why Not Use Transform?

Manual iteration provides more control for stateful processing (tracking current section).
