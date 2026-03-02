# frozen_string_literal: true

# A small example that shows a really small parser and what happens on parser
# errors.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'pp'
require 'parsanol/parslet'

class MyParser < Parsanol::Parser
  rule(:a) { str('a').repeat }

  def parse(str)
    a.parse(str)
  end
end

pp MyParser.new.parse('aaaa')
pp MyParser.new.parse('bbbb')
