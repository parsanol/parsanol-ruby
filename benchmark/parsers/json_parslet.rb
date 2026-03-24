# frozen_string_literal: true

# JSON Parser using original Parslet
# Used as baseline for performance comparison

require "parslet"

class JsonParsletParser < Parslet::Parser
  # Whitespace
  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }

  # Basic values
  rule(:string) do
    str('"') >>
      ((str("\\") >> any) | (str('"').absent? >> any)).repeat >>
      str('"')
  end

  rule(:number) do
    str("-").maybe >>
      match("[0-9]").repeat(1) >>
      (str(".") >> match("[0-9]").repeat(1)).maybe >>
      (match("[eE]") >> match("[+-]").maybe >> match("[0-9]").repeat(1)).maybe
  end

  rule(:true_val) { str("true").as(true) }
  rule(:false_val) { str("false").as(false) }
  rule(:null_val) { str("null").as(:null) }

  # Arrays and objects
  rule(:array) do
    str("[") >> space? >>
      (value >> (space? >> str(",") >> space? >> value).repeat).maybe.as(:array) >>
      space? >> str("]")
  end

  rule(:object) do
    str("{") >> space? >>
      (pair >> (space? >> str(",") >> space? >> pair).repeat).maybe.as(:object) >>
      space? >> str("}")
  end

  rule(:pair) do
    string.as(:key) >> space? >> str(":") >> space? >> value.as(:value)
  end

  # Value
  rule(:value) do
    string.as(:string) |
      number.as(:number) |
      object |
      array |
      true_val |
      false_val |
      null_val
  end

  rule(:json) { space? >> value >> space? }
  root :json
end

# Transform for converting parse tree to Ruby objects
class JsonParsletTransform < Parslet::Transform
  rule(true => simple(:x)) { true }
  rule(false => simple(:x)) { false }
  rule(null: simple(:x)) { nil }
  rule(string: simple(:s)) { s.to_s.gsub(/^"|"$/, "") }
  rule(number: simple(:n)) { n.to_s.to_f }
  rule(array: sequence(:a)) { a }
  rule(array: simple(:x)) { [] }
  rule(object: sequence(:pairs)) do
    pairs.to_h do |p|
      [p[:key], p[:value]]
    end
  end
  rule(object: simple(:x)) { {} }
  rule(key: simple(:k), value: simple(:v)) { { k.to_s.gsub(/^"|"$/, "") => v } }
end
