# frozen_string_literal: true

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

# This example demonstrates how to do deepest error reporting, as invented
# by John Mettraux (issue #64).

require 'parsanol/parslet'
require 'parsanol/convenience'

def prettify(str)
  puts "#{' ' * 3}#{' ' * 4}.#{' ' * 4}10#{' ' * 3}.#{' ' * 4}20"
  str.lines.each_with_index do |line, index|
    printf "%02d %s\n",
           index + 1,
           line.chomp
  end
end

class MyParser < Parsanol::Parser
  # commons

  rule(:space) { match('[ \t]').repeat(1) }
  rule(:space?) { space.maybe }

  rule(:newline) { match('[\r\n]') }

  rule(:comment) { str('#') >> match('[^\r\n]').repeat }

  rule(:line_separator) do
    (space? >> ((comment.maybe >> newline) | str(';')) >> space?).repeat(1)
  end

  rule(:blank) { line_separator | space }
  rule(:blank?) { blank.maybe }

  rule(:identifier) { match('[a-zA-Z0-9_]').repeat(1) }

  # res_statement

  rule(:reference) do
    (str('@').repeat(1, 2) >> identifier).as(:reference)
  end

  rule(:res_action_or_link) do
    str('.').as(:dot) >> (identifier >> str('?').maybe).as(:name) >> str('()')
  end

  rule(:res_actions) do
    reference.as(:resources) >>
      res_action_or_link.as(:res_action).repeat(0).as(:res_actions)
  end

  rule(:res_statement) do
    res_actions >>
      (str(':') >> identifier.as(:name)).maybe.as(:res_field)
  end

  # expression

  rule(:expression) do
    res_statement
  end

  # body

  rule(:body) do
    (line_separator >> (block | expression)).repeat(1).as(:body) >>
      line_separator
  end

  # blocks

  rule(:begin_block) do
    (str('concurrent').as(:type) >> space).maybe.as(:pre) >>
      str('begin').as(:begin) >>
      body >>
      str('end')
  end

  rule(:define_block) do
    str('define').as(:define) >> space >>
      identifier.as(:name) >> str('()') >>
      body >>
      str('end')
  end

  rule(:block) do
    define_block | begin_block
  end

  # root

  rule(:radix) do
    line_separator.maybe >> block >> line_separator.maybe
  end

  root(:radix)
end

ds = [
  %{
    define f()
      @res.name
    end
  },
  %{
    define f()
      begin
        @res.name
      end
    end
  }
]

ds.each do |d|
  puts '-' * 80
  prettify(d)

  parser = MyParser.new

  parser.parse_with_debug(d,
                          reporter: Parsanol::ErrorReporter::Deepest.new)
end

puts '-' * 80
