# frozen_string_literal: true

# URL Parser Example - Basic Parsing
#
# This example demonstrates parsing URLs into their components.
# Shows protocol, host, port, path, query string, and fragment parsing.
#
# Run with: ruby -Ilib example/url_ruby_transform.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol'

# Step 1: Define the URL grammar
class UrlParser < Parsanol::Parser
  root :url

  rule(:url) do
    protocol.as(:protocol) >>
      str('://') >>
      host.as(:host) >>
      port.maybe.as(:port) >>
      path.maybe.as(:path) >>
      query.maybe.as(:query) >>
      fragment.maybe.as(:fragment)
  end

  rule(:protocol) { str('http') | str('https') | str('ftp') | str('ws') | str('wss') }

  rule(:host) do
    (domain | ip_address).as(:address)
  end

  rule(:domain) do
    label >> (str('.') >> label).repeat
  end

  rule(:label) do
    match('[a-zA-Z0-9]').repeat(1)
  end

  rule(:ip_address) do
    octet >> str('.') >> octet >> str('.') >> octet >> str('.') >> octet
  end

  rule(:octet) do
    match('[0-9]').repeat(1, 3)
  end

  rule(:port) do
    str(':') >> match('[0-9]').repeat(1).as(:number)
  end

  rule(:path) do
    str('/') >> path_segment.repeat(1).as(:segments)
  end

  rule(:path_segment) do
    match('[^/?#]').repeat(1) >> str('/').maybe
  end

  rule(:query) do
    str('?') >> query_string.as(:string)
  end

  rule(:query_string) do
    match('[^#]').repeat
  end

  rule(:fragment) do
    str('#') >> match('.').repeat.as(:value)
  end
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
  ) do
    port_num = port&.dig(:number)&.to_i
    ParsedURL.new(
      protocol: p.to_s,
      host: h[:address].to_s,
      port: port_num,
      path: path&.dig(:segments)&.to_s,
      query: q&.dig(:string)&.to_s,
      fragment: f.to_s
    )
  end

  rule(
    protocol: simple(:p),
    host: simple(:h),
    port: simple(:port),
    path: simple(:path),
    query: simple(:q)
  ) do
    port_num = port&.dig(:number)&.to_i
    ParsedURL.new(
      protocol: p.to_s,
      host: h[:address].to_s,
      port: port_num,
      path: path&.dig(:segments)&.to_s,
      query: q&.dig(:string)&.to_s
    )
  end

  rule(
    protocol: simple(:p),
    host: simple(:h),
    port: simple(:port),
    path: simple(:path)
  ) do
    port_num = port&.dig(:number)&.to_i
    ParsedURL.new(
      protocol: p.to_s,
      host: h[:address].to_s,
      port: port_num,
      path: path&.dig(:segments)&.to_s
    )
  end

  rule(protocol: simple(:p), host: simple(:h), port: simple(:port)) do
    ParsedURL.new(
      protocol: p.to_s,
      host: h[:address].to_s,
      port: port&.dig(:number)&.to_i
    )
  end

  rule(protocol: simple(:p), host: simple(:h)) do
    ParsedURL.new(protocol: p.to_s, host: h[:address].to_s)
  end
end

def parse_url(input)
  parser = UrlParser.new
  tree = parser.parse(input)

  transform = UrlTransform.new
  transform.apply(tree)
rescue Parsanol::ParseFailed => e
  puts "Parse failed: #{e.message}"
  nil
end

if __FILE__ == $PROGRAM_NAME
  puts '=' * 60
  puts 'URL Parser - Basic Parsing'
  puts '=' * 60
  puts

  test_urls = [
    'http://example.com',
    'https://example.com:8080',
    'https://example.com/path/to/resource',
    'https://example.com/search?q=ruby&limit=10',
    'https://example.com/page#section',
    'https://api.example.com:443/v1/users?id=123#results',
    'http://192.168.1.1:3000/admin',
    'ws://websocket.example.com/socket'
  ]

  test_urls.each do |url_str|
    puts '-' * 40
    puts "Input: #{url_str}"
    url = parse_url(url_str)
    if url
      puts "  Protocol: #{url.protocol}"
      puts "  Host: #{url.host}"
      puts "  Port: #{url.port || '(default)'}"
      puts "  Path: #{url.path || '/'}"
      puts "  Query: #{url.query || '(none)'}"
      puts "  Fragment: #{url.fragment || '(none)'}"
      puts "  Reconstructed: #{url}"
    end
    puts
  end
end
