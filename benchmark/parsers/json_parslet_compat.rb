# frozen_string_literal: true

# JSON Parser using Parsanol::Parslet compatibility layer
# Drop-in replacement for Parslet

require 'parsanol/parslet'

class JsonParsletCompatParser < Parsanol::Parslet::Parser
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
