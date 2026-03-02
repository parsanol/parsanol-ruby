# Simple XML Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/simple-xml
ruby basic.rb
```

## Code Walkthrough

### Document Rule

Documents are nested tag pairs with content:

```ruby
rule(:document) {
  tag(close: false).as(:o) >> document.as(:i) >> tag(close: true).as(:c) |
  text
}
```

Recursive structure allows arbitrary nesting depth.

### Tag Rule with Parameter

Tags are generated dynamically based on open/close state:

```ruby
def tag(opts={})
  close = opts[:close] || false

  parslet = str('<')
  parslet = parslet >> str('/') if close
  parslet = parslet >> (str('>').absent? >> match("[a-zA-Z]")).repeat(1).as(:name)
  parslet = parslet >> str('>')

  parslet
end
```

Method generates opening `<tag>` or closing `</tag>` patterns.

### Text Rule

Text content excludes angle brackets:

```ruby
rule(:text) {
  match('[^<>]').repeat(0)
}
```

Simple character class prevents tag confusion.

### Tag Validation via Transform

A transform validates matching open/close tags:

```ruby
t = Parsanol::Transform.new do
  rule(
    o: {name: simple(:tag)},
    c: {name: simple(:tag)},
    i: simple(:t)
  ) { 'verified' }
end
```

Pattern matching ensures both tags have the same name.

### Validation Logic

If tags don't match, the transform fails:

```ruby
def check(xml)
  r = XML.new.parse(xml)
  t = Parsanol::Transform.new do
    rule(
      o: {name: simple(:tag)},
      c: {name: simple(:tag)},
      i: simple(:t)
    ) { 'verified' }
  end
  t.apply(r)
end
```

Returns 'verified' for valid XML, fails otherwise.

## Output Types

```ruby
# Valid XML:
{
  o: {name: "a"},
  i: {
    o: {name: "b"},
    i: "some text in the tags",
    c: {name: "b"}
  },
  c: {name: "a"}
}

# After validation:
"verified"

# Mismatched tags:
# Transform fails (pattern doesn't match)
```

## Design Decisions

### Why Validate via Transform?

Transforms can express constraints that are hard to encode in the grammar itself.

### Why Method Instead of Rule for Tags?

`tag(close: true/false)` demonstrates dynamic rule generation, useful for related patterns.

### Why Not Full XML?

This is a teaching example. Real XML requires handling attributes, namespaces, CDATA, etc.
