# URL Parser - Ruby Implementation

## How to Run

```bash
cd parsanol-ruby/example/url
ruby basic.rb
```

## Code Walkthrough

### URL Structure Rule

URLs have ordered components:

```ruby
rule(:url) {
  protocol.as(:protocol) >>
  str('://') >>
  host.as(:host) >>
  port.maybe.as(:port) >>
  path.maybe.as(:path) >>
  query.maybe.as(:query) >>
  fragment.maybe.as(:fragment)
}
```

Each component is optional except protocol and host.

### Protocol Rule

Common protocols are supported:

```ruby
rule(:protocol) {
  (str('http') | str('https') | str('ftp') | str('ws') | str('wss'))
}
```

HTTP, FTP, and WebSocket protocols are recognized.

### Host Rule

Hosts can be domains or IP addresses:

```ruby
rule(:host) {
  (domain | ip_address).as(:address)
}

rule(:domain) {
  label >> (str('.') >> label).repeat
}

rule(:ip_address) {
  octet >> str('.') >> octet >> str('.') >> octet >> str('.') >> octet
}
```

Alternation allows either format.

### Path and Query Rules

Path segments and query strings:

```ruby
rule(:path) {
  str('/') >> path_segment.repeat(1).as(:segments)
}

rule(:query) {
  str('?') >> query_string.as(:string)
}

rule(:fragment) {
  str('#') >> match('.').repeat.as(:value)
}
```

Markers (`/`, `?`, `#`) identify each component.

### ParsedURL Helper Class

A class provides convenient access:

```ruby
class ParsedURL
  attr_reader :protocol, :host, :port, :path, :query, :fragment

  def path_segments
    @path ? @path.split('/').reject(&:empty?) : []
  end

  def query_params
    return {} unless @query
    @query.split('&').each_with_object({}) do |pair, hash|
      key, value = pair.split('=', 2)
      hash[key] = value || ''
    end
  end
end
```

Helper methods parse query strings and paths.

### Transform Rules

Multiple transform rules handle optional components:

```ruby
class UrlTransform < Parsanol::Transform
  rule(protocol: simple(:p), host: simple(:h), port: simple(:port), ...) { ... }
  rule(protocol: simple(:p), host: simple(:h), port: simple(:port)) { ... }
  rule(protocol: simple(:p), host: simple(:h)) { ... }
end
```

Each rule matches a specific combination of present components.

## Output Types

```ruby
# Parse tree for "https://example.com:8080/path?q=1#anchor":
{:protocol=>"https", :host=>{:address=>"example.com"}, :port=>{:number=>"8080"}, ...}

# After transform:
#<ParsedURL @protocol="https", @host="example.com", @port=8080, @path="/path", @query="q=1", @fragment="anchor">
```

## Design Decisions

### Why Multiple Transform Rules?

Different URLs have different components. Multiple rules handle all valid combinations.

### Why Helper Class Instead of Hash?

`ParsedURL` provides type-safe access and utility methods like `query_params`.

### Why Maybe for Optional Components?

`.maybe` returns nil when absent, simplifying pattern matching in transforms.
