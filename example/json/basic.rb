# frozen_string_literal: true

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

#
# MIT License - (c) 2011 John Mettraux
#

require "rubygems"
require "parsanol/parslet" # gem install parslet

module MyJson
  class Parser < Parsanol::Parser
    rule(:spaces) { match('\s').repeat(1) }
    rule(:spaces?) { spaces.maybe }

    rule(:comma) { spaces? >> str(",") >> spaces? }
    rule(:digit) { match("[0-9]") }

    rule(:number) do
      (
        str("-").maybe >> (
          str("0") | (match("[1-9]") >> digit.repeat)
        ) >> (
          str(".") >> digit.repeat(1)
        ).maybe >> (
          match("[eE]") >> (str("+") | str("-")).maybe >> digit.repeat(1)
        ).maybe
      ).as(:number)
    end

    rule(:string) do
      str('"') >> (
        (str("\\") >> any) | (str('"').absent? >> any)
      ).repeat.as(:string) >> str('"')
    end

    rule(:array) do
      str("[") >> spaces? >>
        (value >> (comma >> value).repeat).maybe.as(:array) >>
        spaces? >> str("]")
    end

    rule(:object) do
      str("{") >> spaces? >>
        (entry >> (comma >> entry).repeat).maybe.as(:object) >>
        spaces? >> str("}")
    end

    rule(:value) do
      string | number |
        object | array |
        str("true").as(true) | str("false").as(false) |
        str("null").as(:null)
    end

    rule(:entry) do
      (
         string.as(:key) >> spaces? >>
         str(":") >> spaces? >>
         value.as(:val)
       ).as(:entry)
    end

    rule(:attribute) { (entry | value).as(:attribute) }

    rule(:top) { spaces? >> value >> spaces? }

    root(:top)
  end

  class Transformer < Parsanol::Transform
    Entry = Struct.new(:key, :val)

    rule(array: subtree(:ar)) do
      ar.is_a?(Array) ? ar : [ar]
    end
    rule(object: subtree(:ob)) do
      (ob.is_a?(Array) ? ob : [ob]).to_h do |e|
        [e.key, e.val]
      end
    end

    rule(entry: { key: simple(:ke), val: simple(:va) }) do
      Entry.new(ke, va)
    end

    rule(string: simple(:st)) do
      st.to_s
    end
    rule(number: simple(:nb)) do
      /[eE.]/.match?(nb) ? Float(nb) : Integer(nb)
    end

    rule(null: simple(:nu)) { nil }
    rule(true => simple(:tr)) { true }
    rule(false => simple(:fa)) { false }
  end

  def self.parse(s)
    parser = Parser.new
    transformer = Transformer.new

    tree = parser.parse(s)
    puts
    p tree
    puts
    transformer.apply(tree)
  end
end

s = %(
  [ 1, 2, 3, null,
    "asdfasdf asdfds", { "a": -1.2 }, { "b": true, "c": false },
    0.1e24, true, false, [ 1 ] ]
)

out = MyJson.parse(s)

p out
puts

out == [
  1, 2, 3, nil,
  "asdfasdf asdfds", { "a" => -1.2 }, { "b" => true, "c" => false },
  0.1e24, true, false, [1]
] || raise("MyJson is a failure")
