# frozen_string_literal: true

# A small example that demonstrates the power of tree pattern matching. Also
# uses '.as(:name)' to construct a tree that can reliably be matched
# afterwards.

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'pp'
require 'parsanol/parslet'

# as in 'lots of insipid and stupid parenthesis'
module LISP
  class Parser < Parsanol::Parser
    rule(:balanced) do
      str('(').as(:l) >> balanced.maybe.as(:m) >> str(')').as(:r)
    end

    root(:balanced)
  end

  class Transform < Parsanol::Transform
    rule(l: '(', m: simple(:x), r: ')') do
      # innermost :m will contain nil
      x.nil? ? 1 : x + 1
    end
  end
end

parser = LISP::Parser.new
transform = LISP::Transform.new
%w[
  ()
  (())
  ((((()))))
  ((())
].each do |pexp|
  begin
    result = parser.parse(pexp)
    puts "#{'%20s' % pexp}: #{result.inspect} (#{transform.apply(result)} parens)"
  rescue Parsanol::ParseFailed => e
    puts "#{'%20s' % pexp}: #{e}"
  end
  puts
end
