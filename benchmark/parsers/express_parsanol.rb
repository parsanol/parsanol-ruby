# frozen_string_literal: true

# Simplified EXPRESS Schema Parser for Benchmarking
# Handles the basic schema structure used in benchmark inputs

require 'parsanol'

class ExpressParsanolParser < Parsanol::Parser
  include Parsanol::RubyTransform

  # Whitespace and comments
  rule(:space) { match('[\s\n\r]').repeat(1) }
  rule(:space?) { space.maybe }
  rule(:ignore) { space.repeat }
  rule(:ignore?) { ignore.maybe }

  # Identifiers
  rule(:identifier) { match('[a-zA-Z]') >> match('[a-zA-Z0-9_]').repeat }

  # Numbers
  rule(:integer) { match('[0-9]').repeat(1) }

  # Keywords
  rule(:schema_kw) { str('SCHEMA') }
  rule(:end_schema_kw) { str('END_SCHEMA') }
  rule(:entity_kw) { str('ENTITY') }
  rule(:end_entity_kw) { str('END_ENTITY') }
  rule(:where_kw) { str('WHERE') }

  # Types
  rule(:simple_type) {
    str('INTEGER') | str('STRING') | str('REAL') |
    str('BOOLEAN') | str('NUMBER')
  }

  # Attribute declaration
  rule(:attribute) {
    identifier.as(:attr_name) >> space? >> str(':') >> space? >>
    simple_type.as(:attr_type) >> space? >> str(';') >> ignore?
  }

  # WHERE clause rule (simplified)
  rule(:where_rule) {
    ignore? >> identifier.as(:rule_name) >> space? >> str(':') >> space? >>
    identifier.as(:var) >> space? >> str('>=') >> space? >> integer.as(:value) >>
    space? >> str(';')
  }

  # WHERE clause
  rule(:where_clause) {
    where_kw >> ignore? >> where_rule.repeat(1).as(:where_rules)
  }

  # Entity declaration
  rule(:entity_decl) {
    ignore? >> entity_kw >> space >> identifier.as(:entity_name) >> space? >> str(';') >>
    ignore? >> attribute.repeat(1).as(:attributes) >> ignore? >>
    (where_clause >> ignore?).maybe >>
    end_entity_kw >> str(';')
  }

  # Schema declaration
  rule(:schema_decl) {
    schema_kw >> space >> identifier.as(:schema_name) >> space? >> str(';') >>
    ignore? >> entity_decl.repeat.as(:entities) >> ignore? >>
    end_schema_kw >> str(';')
  }

  rule(:schema) { ignore? >> schema_decl.as(:schema) >> ignore? }
  root :schema
end
