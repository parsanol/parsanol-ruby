# ERB Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/erb
ruby basic.rb
```

## Code Walkthrough

### ERB Tag Content Rule

The ruby content inside ERB tags excludes the closing delimiter:

```ruby
rule(:ruby) { (str('%>').absent? >> any).repeat.as(:ruby) }
```

Negative lookahead prevents premature termination when parsing embedded Ruby code.

### ERB Expression Types

Three types of ERB tags are supported:

```ruby
rule(:expression) { (str('=') >> ruby).as(:expression) }
rule(:comment) { (str('#') >> ruby).as(:comment) }
rule(:code) { ruby.as(:code) }
rule(:erb) { expression | comment | code }
```

- Expression (`<%= %>`) outputs values
- Comment (`<%# %>`) is ignored
- Code (`<% %>`) executes without output

### Complete ERB Tag

Tags combine opening delimiter, content, and closing delimiter:

```ruby
rule(:erb_with_tags) { str('<%') >> erb >> str('%>') }
```

The `erb` rule handles the type prefix (=, #, or nothing).

### Text and Template Body

Text content excludes ERB opening tags:

```ruby
rule(:text) { (str('<%').absent? >> any).repeat(1) }
rule(:text_with_ruby) { (text.as(:text) | erb_with_tags).repeat.as(:text) }
```

Alternation between text and ERB tags allows interleaving.

### Transform for Evaluation

The transform evaluates Ruby code:

```ruby
evaluator = Parsanol::Transform.new do
  erb_binding = binding

  rule(:code => { :ruby => simple(:ruby) }) { eval(ruby, erb_binding); '' }
  rule(:expression => { :ruby => simple(:ruby) }) { eval(ruby, erb_binding) }
  rule(:comment => { :ruby => simple(:ruby) }) { '' }

  rule(:text => simple(:text)) { text }
  rule(:text => sequence(:texts)) { texts.join }
end
```

Code blocks execute silently; expressions return values; comments produce empty strings.

## Output Types

```ruby
# Parse tree:
{:text=>[
  {:text=>"The value of x is "@s},
  {:expression=>{:ruby=>" x "@s}},
  {:text=>"."@s}
]}

# After transform (evaluated):
"The value of x is 42."
```

## Design Decisions

### Why Separate Expression and Code Tags?

`<%= %>` outputs the result, `<% %>` executes for side effects. This distinction is fundamental to template evaluation.

### Why Use Binding in Transform?

A shared binding allows code in one tag to affect later expressions (e.g., setting a variable).

### Why Comment as Separate Type?

Comments should be completely ignored during evaluation, not parsed as Ruby code.
