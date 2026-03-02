# README Example - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/documentation
ruby basic.rb
```

## Code Walkthrough

### String Parser Construction

This example demonstrates the minimal parser from the README:

```ruby
parser =  str('"') >>
          (
            str('\\') >> any |
            str('"').absent? >> any
          ).repeat.as(:string) >>
          str('"')
```

The parser matches quoted strings with escape sequences.

### Escape Sequence Handling

The pattern `str('\\') >> any` handles escaped characters:

```ruby
# Matches: \" \\ \n etc.
str('\\') >> any
```

Any character following a backslash is accepted.

### String Content Matching

The pattern `str('"').absent? >> any` matches non-quote characters:

```ruby
# Matches any character except "
str('"').absent? >> any
```

Combined with escape handling via alternation.

### Named Capture

`.as(:string)` labels the matched content:

```ruby
tree = parser.parse('"Hello"')
# => {:string=>"Hello"}
```

The result is a hash with the captured content.

### Transform Application

Transforms extract and process captured content:

```ruby
transform = Parsanol::Transform.new do
  rule(:string => simple(:x)) {
    puts "String contents: #{x}"
  }
end
transform.apply(tree)
```

Pattern matching on the tree structure.

## Output Types

```ruby
# Parse result:
{:string=>"This is a \"String\" in which you can escape stuff"}

# Transform output:
String contents: This is a "String" in which you can escape stuff
```

## Design Decisions

### Why This Example?

This is the canonical "hello world" for Parslet-style parsing. It demonstrates the core concepts in minimal form.

### Why Transform?

Transforms separate parsing from processing. The parser creates structure; transforms interpret it.

### Ruby-Only Feature

This example uses Parslet-compatible API for demonstration purposes.
