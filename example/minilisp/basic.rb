# frozen_string_literal: true

# Reproduces [1] using parslet.
# [1] http://thingsaaronmade.com/blog/a-quick-intro-to-writing-a-parser-using-treetop.html

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require "pp"
require "parsanol/parslet"
require "parsanol/convenience"

module MiniLisp
  class Parser < Parsanol::Parser
    root :expression
    rule(:expression) do
      space? >> str("(") >> space? >> body >> str(")") >> space?
    end

    rule(:body) do
      (expression | identifier | float | integer | string).repeat.as(:exp)
    end

    rule(:space) do
      match('\s').repeat(1)
    end
    rule(:space?) do
      space.maybe
    end

    rule(:identifier) do
      (match("[a-zA-Z=*]") >> match("[a-zA-Z=*_]").repeat).as(:identifier) >> space?
    end

    rule(:float) do
      (
        integer >> (
          (str(".") >> match("[0-9]").repeat(1)) |
          (str("e") >> match("[0-9]").repeat(1))
        ).as(:e)
      ).as(:float) >> space?
    end

    rule(:integer) do
      ((str("+") | str("-")).maybe >> match("[0-9]").repeat(1)).as(:integer) >> space?
    end

    rule(:string) do
      str('"') >> (
        (str("\\") >> any) |
        (str('"').absent? >> any)
      ).repeat.as(:string) >> str('"') >> space?
    end
  end

  class Transform
    include Parsanol::Parslet

    attr_reader :t

    def initialize
      @t = Parsanol::Transform.new

      # To understand these, take a look at what comes out of the parser.
      t.rule(identifier: simple(:ident)) { ident.to_sym }

      t.rule(string: simple(:str))       { str }

      t.rule(integer: simple(:int))      { Integer(int) }

      t.rule(float: { integer: simple(:a), e: simple(:b) }) { Float(a + b) }

      t.rule(exp: subtree(:exp)) { exp }
    end

    def do(tree)
      t.apply(tree)
    end
  end
end

parser = MiniLisp::Parser.new
transform = MiniLisp::Transform.new

result = parser.parse_with_debug %{
  (define test (lambda ()
    (begin
      (display "something")
      (display 1)
      (display 3.08))))
}

# Transform the result
pp transform.do(result) if result

# Thereby reducing it to the earlier problem:
# http://github.com/kschiess/toylisp
