# INI Parser Example - RubyTransform
#
# This example demonstrates parsing INI configuration files.
# Shows section headers, key-value pairs, and comments.
#
# Run with: ruby -Ilib example/ini_ruby_transform.rb

$:.unshift File.dirname(__FILE__) + "/../lib"

require 'parsanol'

# Step 1: Define the INI file grammar
class IniParser < Parsanol::Parser
  root :ini

  rule(:ini) {
    (section | key_value | comment).repeat
  }

  # Section header: [section_name]
  rule(:section) {
    (space? >> str('[') >> section_name.as(:name) >> str(']') >> space? >> str("\n").maybe).as(:section)
  }

  rule(:section_name) {
    (match('[^]\n]').repeat(1))
  }

  # Key-Value pair: key = value
  rule(:key_value) {
    (space? >> key.as(:key) >> space? >> str('=') >> space? >> value.as(:value) >> space? >> str("\n").maybe).as(:kv)
  }

  rule(:key) {
    match('[^\s=]').repeat(1)
  }

  rule(:value) {
    (match('[^\n]').repeat)
  }

  # Comment: # or ; at start of line
  rule(:comment) {
    (space? >> (str('#') | str(';')) >> match('[^\n]').repeat >> str("\n").maybe).as(:comment)
  }

  rule(:space?) { match('\s').repeat }
end

# Step 2: INI data structures
class IniFile
  attr_reader :sections

  def initialize
    @sections = {}
    @current_section = nil
  end

  def set_section(name)
    @current_section = name
    @sections[name] ||= {}
  end

  def set_key_value(key, value)
    section = @sections[@current_section] || {}
    section[key.to_s.strip] = value.to_s.strip
    @sections[@current_section] = section
  end

  def get(section, key = nil)
    if key
      @sections[section]&.[](key)
    else
      @sections[section] || {}
    end
  end

  def to_h
    @sections
  end
end

# Step 3: Parse and transform
def parse_ini(input)
  parser = IniParser.new
  tree = parser.parse(input)

  puts "Parse tree: #{tree.inspect[0..500]}..."

  ini = IniFile.new

  tree.each do |item|
    case item
    when Hash
      if item[:section]
        name = item[:section][:name].to_s.strip
        ini.set_section(name)
        puts "  Section: [#{name}]"
      elsif item[:kv]
        key = item[:kv][:key].to_s
        value = item[:kv][:value].to_s
        ini.set_key_value(key, value)
        puts "  #{key} = #{value}"
      elsif item[:comment]
        # Skip comments
      end
    end
  end

  ini
end

# Example usage
if __FILE__ == $0
  puts "=" * 60
  puts "INI Parser - RubyTransform"
  puts "=" * 60
  puts

  ini_content = <<~INI
    # This is a comment
    ; This is also a comment

    [database]
    host = localhost
    port = 5432

    [server]
    host = 0.0.0.0
    port = 8080
    debug = true

    [cache]
    enabled = true
    ttl = 3600
  INI

  puts "Input:"
  puts "-" * 40
  puts ini_content
  puts
  puts "Parsed:"
  puts "-" * 40

  ini = parse_ini(ini_content)

  puts
  puts "=" * 60
  puts "Accessing parsed data:"
  puts "=" * 60
  puts "database.host: #{ini.get('database', 'host')}"
  puts "database.port: #{ini.get('database', 'port')}"
  puts "server.debug: #{ini.get('server', 'debug')}"
end
