# Capture Patterns - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/capture
ruby basic.rb
```

## Code Walkthrough

### Capture Mechanism

The `capture(:name)` method captures matched text for later reference:

```ruby
rule(:marker) { match['A-Z'].repeat(1).capture(:marker) }
```

This captures the heredoc marker (like `CAPTURE` or `FOOBAR`) in the context.

### Dynamic Matching

The `dynamic` block accesses captured values:

```ruby
rule(:captured_marker) {
  dynamic { |source, context|
    str(context.captures[:marker])
  }
}
```

`context.captures[:marker]` returns the previously captured string.

### Scope Isolation

The `scope` block creates isolated capture contexts:

```ruby
rule(:document) { scope { doc_start >> text >> doc_end } }
```

Each document has its own capture namespace, allowing nested heredocs.

### Document Structure

Heredoc-style documents with nested content:

```ruby
rule(:text) {
  (document.as(:doc) | text_line.as(:line)).repeat(1)
}
```

Documents can contain other documents (nested heredocs).

### End Marker Matching

The end marker must match the start marker:

```ruby
rule(:doc_end) { captured_marker }
```

This ensures `<FOOBAR` ... `FOOBAR` pairs are correctly matched.

## Output Types

```ruby
# Input:
# <CAPTURE
# Text1
# <FOOBAR
# Text3
# FOOBAR
# Text2
# CAPTURE

# Parse tree (simplified):
{:doc=>[
  {:line=>"Text1\n"},
  {:doc=>[
    {:line=>"Text3\n"}
  ]},
  {:line=>"Text2\n"}
]}
```

## Design Decisions

### Why Capture Instead of Backreference?

Parslet's capture is more powerful than regex backreferences. It integrates with the parsing context and supports nesting.

### Why Scope Blocks?

Without scopes, nested documents would share the same capture namespace. Scopes isolate each document's captures.

### Why Dynamic Blocks?

Dynamic blocks provide access to the parsing context at parse time. This enables context-dependent matching.

### Ruby-Only Feature

This feature uses Parslet's `capture`, `dynamic`, and `scope` constructs. These have no direct equivalent in Rust and are specific to Parslet's Ruby implementation.
