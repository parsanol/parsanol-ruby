# Sentence Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/sentence
ruby basic.rb
```

## Code Walkthrough

### Japanese Sentence Rule

Sentences end with the Japanese period character:

```ruby
rule(:sentence) { (match('[^。]').repeat(1) >> str("。")).as(:sentence) }
```

The character `。` (U+3002) is the CJK full stop, used as sentence delimiter.

### Multiple Sentences Rule

Text is a sequence of sentences:

```ruby
rule(:sentences) { sentence.repeat }
root(:sentences)
```

Repetition handles arbitrary-length text.

### Transform Rule

The transform extracts sentence content:

```ruby
class Transformer < Parsanol::Transform
  rule(:sentence => simple(:sen)) { sen.to_s }
end
```

Pattern matching extracts the captured string value.

### Unicode Handling

Ruby 1.9+ handles Unicode natively:

```ruby
# encoding: UTF-8
```

The encoding pragma ensures proper interpretation of multibyte characters.

## Output Types

```ruby
# Parse tree:
[
  {:sentence=>"RubyKaigi2009のテーマは、「変わる／変える」です"@s},
  {:sentence=>" 前回のRubyKaigi2008のテーマであった..."@s}
]

# After transform:
["RubyKaigi2009のテーマは、「変わる／変える」です。",
 " 前回のRubyKaigi2008のテーマであった..."]
```

## Design Decisions

### Why Use Japanese Period Character?

Natural language parsing must respect language-specific punctuation. Japanese uses `。` not `.`.

### Why Simple Character Class?

`[^。]` excludes only the delimiter. This is simpler than defining valid Japanese character ranges.

### Why Transform to Strings?

Extracting plain strings makes the result easy to process further (count words, analyze sentiment, etc.).
