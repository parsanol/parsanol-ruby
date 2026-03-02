# Mathn Compatibility - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/mathn
ruby basic.rb
```

## Code Walkthrough

### The Mathn Problem

Ruby's deprecated `mathn` library changed integer division behavior:

```ruby
# Without mathn:
3 / 2  # => 1 (integer division)

# With mathn:
3 / 2  # => (3/2) (Rational)
```

This broke Parslet's internal calculations.

### The Grammar

Simple cephalopod matching:

```ruby
cephalopod =
  str('octopus') |
  str('squid')

parenthesized_cephalopod =
  str('(') >>
  possible_whitespace >>
  cephalopod >>
  possible_whitespace >>
  str(')')
```

### The Compatibility Fix

Parsanol includes a fix that works regardless of mathn:

```ruby
def attempt_parse
  parser = possible_whitespace >>
           parenthesized_cephalopod >>
           possible_whitespace

  # This would hang without the fix
  parser.parse %{(\nsqeed)\n}
rescue Parsanol::ParseFailed
end
```

### Version Check

The example checks Ruby version:

```ruby
if RUBY_VERSION.gsub(/[^\d]/, '').to_i < 250
  require 'mathn'
end
```

Mathn was deprecated in Ruby 2.5, so it's only loaded on older Rubies.

## Output Types

```
it terminates before we require mathn
requiring mathn now
and trying again (will hang without the fix)
okay!
```

## Design Decisions

### Why This Example?

It documents a historical compatibility issue. Users encountering similar problems can find this reference.

### Why Keep Mathn Support?

Some legacy systems still use mathn. Parsanol aims for broad Ruby version compatibility.

### Ruby-Only Feature

This is purely about Ruby library compatibility. Rust has no equivalent issue.

### Modern Relevance

As of Ruby 2.5+, mathn is deprecated. This example is mostly historical but demonstrates Parslet's robustness.
