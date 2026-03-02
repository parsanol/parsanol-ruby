# URL Parser Example - RubyTransform: Ruby Transform
#
# This example demonstrates parsing URLs into their components.
# Shows protocol, host, port, path, query string, and fragment parsing.
#
# Run with: ruby -Ilib example/url_ruby_transform.rb

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol'

# Step 1: Define the URL grammar
class UrlParser < Parsanol::Parser
  root :url

  rule(:url) {
    protocol.as(:protocol) >>
    str('://') >>
    host.as(:host) >>
    port.maybe.as(:port) >>
    path.maybe.as(:path) >>
    query.maybe.as(:query) >>
    fragment.maybe.as(:fragment)
  }

  rule(:protocol) { (str('http') | str('https') | str('ftp') | str('ws') | str('wss')) }

  rule(:host) {
    (domain | ip_address).as(:address)
  }

  rule(:domain) {
    label >> (str('.') >> label).repeat
  }

  rule(:label) {
    match('[a-zA-Z0-9]').repeat(1)
  }

  rule(:ip_address) {
    octet >> str('.') >> octet >> str('.') >> octet >> str('.') >> octet
  }

  rule(:octet) {
    match('[0-9]').repeat(1, 3)
  }

  rule(:port) {
    str(':') >> match('[0-9]').repeat(1).as(:number)
  }

  rule(:path) {
    str('/') >> path_segment.repeat(1).as(:segments)
  }

  rule(:path_segment) {
    (match('[^/?#]').repeat(1) >> str('/').maybe)
  }

  rule(:query) {
    str('?') >> query_string.as(:string)
  }

  rule(:query_string) {
    match('[^#]').repeat
  }

  rule(:fragment) {
    str('#') >> match('.').repeat.as(:value)
  }
end

# Step 2: URL class
class ParsedURL
  attr_reader :protocol, :host, :port, :path, :query, :fragment

  def initialize(protocol:, host:, port: nil, path: nil, query: nil, fragment: nil)
    @protocol = protocol
    @host = host
    @port = port
    @path = path
    @query = query
    @fragment = fragment
  end

  def to_s
    url = "#{@protocol}://#{@host}"
    url += ":#{@port}" if @port
    url += @path if @path
    url += "?#{@query}" if @query
    url += "##{@fragment}" if @fragment
    url
  end

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

# Step 3: Transform
class UrlTransform < Parsanol::Transform
  rule(
    protocol: simple(:p),
    host: simple(:h),
    port: simple(:port),
    path: simple(:path),
    query: simple(:q),
    fragment: simple(:f)
  ) {
    port_num = port&.dig(:number)&.to_i
    ParsedURL.new(
      protocol: p.to_s,
      host: h[:address].to_s,
      port: port_num,
      path: path&.dig(:segments)&.to_s,
      query: q&.dig(:string)&.to_s,
      fragment: f.to_s
    )
  }

  rule(
    protocol: simple(:p),
    host: simple(:h),
    port: simple(:port),
    path: simple(:path),
    query: simple(:q)
  ) {
    port_num = port&.dig(:number)&.to_i
    ParsedURL.new(
      protocol: p.to_s,
      host: h[:address].to_s,
      port: port_num,
      path: path&.dig(:segments)&.to_s,
      query: q&.dig(:string)&.to_s
    )
  }

  rule(
    protocol: simple(:p),
    host: simple(:h),
    port: simple(:port),
    path: simple(:path)
  ) {
    port_num = port&.dig(:number)&.to_i
    ParsedURL.new(
      protocol: p.to_s,
      host: h[:address].to_s,
      port: port_num,
      path: path&.dig(:segments)&.to_s
    )
  }

  rule(protocol: simple(:p), host: simple(:h), port: simple(:port)) {
    ParsedURL.new(
      protocol: p.to_s,
      host: h[:address].to_s,
      port: port&.dig(:number)&.to_i
    )
  }

  rule(protocol: simple(:p), host: simple(:h)) {
    ParsedURL.new(protocol: p.to_s, host: h[:address].to_s)
  }
end

def parse_url(input)
  parser = UrlParser.new
  tree = parser.parse(input)

  transform = UrlTransform.new
  url = transform.apply(tree)

  url
rescue Parsanol::ParseFailed => e
  puts "Parse failed: #{e.message}"
  nil
end

if __FILE__ == $0
  puts "=" * 60
  puts "URL Parser - RubyTransform"
  puts "=" * 60
  puts

  test_urls = [
    "http://example.com",
    "https://example.com:8080",
    "https://example.com/path/to/resource",
    "https://example.com/search?q=ruby&limit=10",
    "https://example.com/page#section",
    "https://api.example.com:443/v1/users?id=123#results",
    "http://192.168.1.1:3000/admin",
    "ws://websocket.example.com/socket",
  ]

  test_urls.each do |url_str|
    puts "-" * 40
    puts "Input: #{url_str}"
    url = parse_url(url_str)
    if url
      puts "  Protocol: #{url.protocol}"
      puts "  Host: #{url.host}"
      puts "  Port: #{url.port || '(default)'}"
      puts "  Path: #{url.path || '/'}"
      puts "  Query: #{url.query || '(none)'}"
      puts "  Fragment: #{url.fragment || '(none)'}"
      puts "  Reconstructed: #{url.to_s}"
    end
    puts
  end
end
