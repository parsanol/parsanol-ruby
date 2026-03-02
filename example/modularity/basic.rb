# frozen_string_literal: true

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'pp'
require 'parsanol/parslet'

# Demonstrates modular parsers, split out over many classes. Please look at
# ip_address.rb as well.

module ALanguage
  include Parsanol::Parslet

  # Parslet rules are really a special kind of method. Mix them into your
  # classes!
  rule(:a_language) { str('aaa') }
end

# Parslet parsers are parslet atoms as well. Create an instance and chain them
# to your other rules.
#
class BLanguage < Parsanol::Parser
  root :blang

  rule(:blang) { str('bbb') }
end

# Parslet atoms are really Ruby values, pass them around.
c_language = Parsanol.str('ccc')

class Language < Parsanol::Parser
  def initialize(c_language)
    @c_language = c_language
    super()
  end

  root :root

  include ALanguage

  rule(:root) do
    (str('a(') >> a_language >> str(')') >> space) |
      (str('b(') >> BLanguage.new >> str(')') >> space) |
      (str('c(') >> @c_language >> str(')') >> space)
  end
  rule(:space) { str(' ').maybe }
end

Language.new(c_language).parse('a(aaa)')
Language.new(c_language).parse('b(bbb)')
Language.new(c_language).parse('c(ccc)')
