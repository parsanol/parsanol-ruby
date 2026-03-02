# IP Address Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/ip-address
ruby basic.rb
```

## Code Walkthrough

### IPv4 DecOctet Rule

Each octet must be 0-255:

```ruby
rule(:dec_octet) {
  str('25') >> match("[0-5]") |
  str('2') >> match("[0-4]") >> digit |
  str('1') >> digit >> digit |
  match('[1-9]') >> digit |
  digit
}
```

Ordered alternatives ensure correct matching: 250-255, 200-249, 100-199, 10-99, 0-9.

### IPv4 Address Rule

Four octets separated by dots:

```ruby
rule(:ipv4) {
  (dec_octet >> str('.') >> dec_octet >> str('.') >>
    dec_octet >> str('.') >> dec_octet).as(:ipv4)
}
```

This matches the dotted-decimal notation from RFC 1123.

### IPv6 H16 Rule

Hexadecimal groups are 1-4 digits:

```ruby
rule(:h16) {
  hexdigit.repeat(1,4)
}

rule(:hexdigit) {
  digit | match("[a-fA-F]")
}
```

Case-insensitive hex matching follows RFC 3986.

### IPv6 Address Rule

IPv6 allows zero compression with `::`:

```ruby
rule(:ipv6) {
  (
    (
      h16r(6) |
      dcolon >> h16r(5) |
      h16.maybe >> dcolon >> h16r(4) |
      # ... more patterns
    ) >> ls32 |
    (h16 >> h16l(5)).maybe >> dcolon >> h16 |
    (h16 >> h16l(6)).maybe >> dcolon
  ).as(:ipv6)
}
```

Multiple alternatives handle different compression positions.

### LS32 Rule

The least-significant 32 bits can be IPv4 or two h16 groups:

```ruby
rule(:ls32) {
  (h16 >> colon >> h16) |
  ipv4
}
```

IPv4-mapped IPv6 addresses are supported.

### Module Composition

Grammar modules are mixed into the parser:

```ruby
module IPv4
  include Parsanol::Parslet
  # IPv4 rules...
end

module IPv6
  include Parsanol::Parslet
  # IPv6 rules...
end

class Parser
  include IPv4
  include IPv6
end
```

Modular organization keeps complex grammar manageable.

## Output Types

```ruby
# IPv4:
{:ipv4=>"192.168.1.1"@s}

# IPv6:
{:ipv6=>"2001:db8::1"@s}

# Invalid:
# Raises Parsanol::ParseFailed
```

## Design Decisions

### Why Separate IPv4 and IPv6 Modules?

RFC 3986 defines them separately; modules allow independent testing and reuse.

### Why So Many IPv6 Alternatives?

Zero compression (`::`) can appear at any position; each alternative represents a valid compression point.

### Why Ordered Alternatives for DecOctet?

PEG parsers try alternatives in order. Largest ranges must come first to prevent premature matching.
