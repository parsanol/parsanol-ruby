# frozen_string_literal: true

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"
require 'parsanol/parslet'

include Parsanol::Parslet

parser = str('a').capture(:a) >> scope { str('b').capture(:a) } >>
         dynamic { |_s, c| str(c.captures[:a]) }

begin
  parser.parse('aba')
  puts "parses 'aba'"
rescue StandardError
  puts 'exception!'
end
