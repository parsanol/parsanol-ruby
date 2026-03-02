# Email Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/email
ruby basic.rb "user@example.com"
```

## Code Walkthrough

### Flexible At Symbol

The parser handles obfuscated email formats:

```ruby
rule(:at) {
  str('@') |
  (dash? >> (str('at') | str('AT')) >> dash?)
}
```

Supports both `@` and `at` (with optional dashes) for spam protection.

### Flexible Dot

Similar flexibility for the dot separator:

```ruby
rule(:dot) {
  str('.') |
  (dash? >> (str('dot') | str('DOT')) >> dash?)
}
```

Handles `user@example.com` and `user at example dot com`.

### Word and Words Rules

Email parts are sequences of words:

```ruby
rule(:word) { match('[a-z0-9]').repeat(1).as(:word) >> space? }
rule(:separator) { dot.as(:dot) >> space? | space }
rule(:words) { word >> (separator >> word).repeat }
```

Words are alphanumeric; separators are dots or spaces.

### Email Structure

The complete email combines username and domain:

```ruby
rule(:email) {
  (words.as(:username) >> space? >> at >> space? >> words).as(:email)
}
```

Labels distinguish local part from domain.

### Sanitizing Transform

The transform normalizes obfuscated emails:

```ruby
class EmailSanitizer < Parsanol::Transform
  rule(:dot => simple(:dot), :word => simple(:word)) { ".#{word}" }
  rule(:word => simple(:word)) { word }

  rule(:username => sequence(:username)) { username.join + "@" }
  rule(:username => simple(:username)) { username.to_s + "@" }

  rule(:email => sequence(:email)) { email.join }
end
```

Converts "user at example dot com" to "user@example.com".

## Output Types

```ruby
# Parse tree for "a.b.c.d@gmail.com":
{:email=>{:username=>[{:word=>"a"}, {:dot=>".", :word=>"b"}, ...], ...}}

# After transform:
"a.b.c.d@gmail.com"
```

## Design Decisions

### Why Handle Obfuscated Formats?

Email addresses are often obfuscated to prevent spam harvesting. This parser can extract and normalize them.

### Why Sequence vs Simple in Transform?

`sequence(:x)` handles arrays of values; `simple(:x)` handles single values. Both cases occur depending on email complexity.

### Why Add @ in Username Transform?

The username rule ends with the @ separator, so the transform adds it back during reconstruction.
