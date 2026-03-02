# Grammar Modularity - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/modularity
ruby basic.rb
```

## Code Walkthrough

### Module Mixins

Ruby modules can be mixed into parser classes:

```ruby
module ALanguage
  include Parsanol::Parslet

  rule(:a_language) { str('aaa') }
end
```

`include Parsanol::Parslet` makes the module a grammar container.

### Parser as Atom

Parser instances are valid atoms:

```ruby
class BLanguage < Parsanol::Parser
  root :blang

  rule(:blang) { str('bbb') }
end
```

Use `BLanguage.new` directly in other parsers' rules.

### Passing Atoms

Atoms are Ruby values that can be passed around:

```ruby
c_language = Parsanol.str('ccc')

class Language < Parsanol::Parser
  def initialize(c_language)
    @c_language = c_language
    super()
  end

  rule(:root) { str('c(') >> @c_language >> str(')') }
end
```

Constructor injection enables dynamic grammar composition.

### Combined Root Rule

The root combines all module entry points:

```ruby
rule(:root) {
  str('a(') >> a_language >> str(')') >> space |
  str('b(') >> BLanguage.new >> str(')') >> space |
  str('c(') >> @c_language >> str(')') >> space
}
```

Each alternative invokes a different module.

### Using the Composed Parser

```ruby
Language.new(c_language).parse('a(aaa)')  # => matches
Language.new(c_language).parse('b(bbb)')  # => matches
Language.new(c_language).parse('c(ccc)')  # => matches
```

Single parser instance handles all module syntaxes.

## Design Patterns

### Include Pattern

```ruby
module CommonExpressions
  include Parsanol::Parslet

  rule(:integer) { match('[0-9]').repeat(1) }
  rule(:identifier) { match('[a-z]').repeat(1) }
end

class MyParser < Parsanol::Parser
  include CommonExpressions
  include WhitespaceRules

  rule(:expr) { integer | identifier }
end
```

Multiple modules combine via include.

### Delegation Pattern

```ruby
class JsonParser < Parsanol::Parser
  rule(:value) { StringParser.new | NumberParser.new | ObjectParser.new }
end
```

Each sub-parser handles one JSON type.

### Prefix Pattern

```ruby
module ExpressionParser
  def expr_with_prefix(prefix)
    prefix >> expr
  end
end
```

Modules can provide parameterized rules.

## Output

```ruby
# All three module syntaxes parse
Language.new(c_language).parse('a(aaa)')
Language.new(c_language).parse('b(bbb)')
Language.new(c_language).parse('c(ccc)')
```

## Design Decisions

### Why Include for Modules?

Ruby's include provides clean namespace integration. Rules become methods on the parser class.

### Why Parser as Atom?

Parsers being atoms enables composition without special syntax. Just instantiate and chain.

### Why Constructor Injection?

Dynamic composition allows runtime grammar modification. Same parser class with different sub-grammars.

### Why Not Class Inheritance?

Composition (include/instance) is more flexible than inheritance. Multiple modules can be combined in any order.
