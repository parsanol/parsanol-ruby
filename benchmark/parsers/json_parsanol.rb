# frozen_string_literal: true

# JSON Parser using Parsanol (both Ruby and Rust backends)
# Same grammar as Parslet version for fair comparison

require 'parsanol'

class JsonParsanolParser < Parsanol::Parser
  include Parsanol::RubyTransform

  # Whitespace
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }

  # Basic values
  rule(:string) {
    str('"') >>
    (str('\\') >> any | str('"').absent? >> any).repeat >>
    str('"')
  }

  rule(:number) {
    str('-').maybe >>
    match('[0-9]').repeat(1) >>
    (str('.') >> match('[0-9]').repeat(1)).maybe >>
    (match('[eE]') >> match('[+-]').maybe >> match('[0-9]').repeat(1)).maybe
  }

  rule(:true_val) { str('true').as(:true) }
  rule(:false_val) { str('false').as(:false) }
  rule(:null_val) { str('null').as(:null) }

  # Arrays and objects
  rule(:array) {
    str('[') >> space? >>
    (value >> (space? >> str(',') >> space? >> value).repeat).maybe.as(:array) >>
    space? >> str(']')
  }

  rule(:object) {
    str('{') >> space? >>
    (pair >> (space? >> str(',') >> space? >> pair).repeat).maybe.as(:object) >>
    space? >> str('}')
  }

  rule(:pair) {
    string.as(:key) >> space? >> str(':') >> space? >> value.as(:value)
  }

  # Value
  rule(:value) {
    string.as(:string) |
    number.as(:number) |
    object |
    array |
    true_val |
    false_val |
    null_val
  }

  rule(:json) { space? >> value >> space? }
  root :json
end

# Transform for converting parse tree to Ruby objects
class JsonParsanolTransform < Parsanol::Transform
  rule(true: simple(:x)) { true }
  rule(false: simple(:x)) { false }
  rule(null: simple(:x)) { nil }
  rule(string: simple(:s)) { s.to_s.gsub(/^"|"$/, '') }
  rule(number: simple(:n)) { n.to_s.to_f }
  rule(array: sequence(:a)) { a }
  rule(array: simple(:x)) { [] }
  rule(object: sequence(:pairs)) { pairs.each_with_object({}) { |p, h| h[p[:key]] = p[:value] } }
  rule(object: simple(:x)) { {} }
  rule(key: simple(:k), value: simple(:v)) { { k.to_s.gsub(/^"|"$/, '') => v } }
end
