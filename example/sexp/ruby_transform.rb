# frozen_string_literal: true

# S-Expression Parser Example - RubyTransform
#
# This example demonstrates parsing Lisp-style S-expressions.
# Shows nested lists, atoms, and quoted strings.
#
# Run with: ruby -Ilib example/sexp_ruby_transform.rb

$LOAD_PATH.unshift "#{File.dirname(__FILE__)}/../lib"

require 'parsanol'

# Step 1: Define the S-expression grammar
class SexpParser < Parsanol::Parser
  root :sexp

  # An S-Expression can be a list or atom
  rule(:sexp) do
    list | atom
  end

  # List: ( ... ) - recursively contains sexps
  rule(:list) do
    str('(') >> elements >> str(')')
  end

  # Elements: zero or more sexps separated by whitespace
  rule(:elements) do
    (sexp >> space?).repeat
  end

  # Atom: number or symbol (whitespace required to separate)
  rule(:atom) do
    number | symbol
  end

  # Symbol: sequence of non-whitespace, non-special chars
  rule(:symbol) do
    match('[^\s\(\)]+')
  end

  # Number: integer or float
  rule(:number) do
    str('-').maybe >>
      match('[0-9]').repeat(1) >>
      (str('.') >> match('[0-9]').repeat).maybe
  end

  rule(:space?) { match('\s').repeat }
end

# Step 2: S-expression node classes
class Sexp; end

class SexpList < Sexp
  attr_reader :elements

  def initialize(elements)
    @elements = elements
  end

  def to_s
    "(#{@elements.join(' ')})"
  end
end

class SexpSymbol < Sexp
  attr_reader :name

  def initialize(name)
    @name = name.to_s
  end

  def to_s
    @name
  end
end

class SexpNumber < Sexp
  attr_reader :value

  def initialize(value)
    @value = value.to_s
  end

  def to_s
    @value
  end
end

# Step 3: Parse and transform
def parse_sexp(input)
  parser = SexpParser.new
  tree = parser.parse(input)

  puts "Parse tree: #{tree.inspect}"

  # Build AST
  ast = build_ast(tree)
  puts "AST: #{ast}"

  ast
rescue Parsanol::ParseFailed => e
  puts "Parse failed: #{e.message}"
  nil
end

def build_ast(tree)
  return nil if tree.nil?

  # Handle slice
  case tree
  when Parsanol::Slice
    s = tree.to_s
    if s.match?(/^-?\d+(\.\d+)?$/)
      SexpNumber.new(s)
    else
      SexpSymbol.new(s)
    end
  when Array
    # It's a list of sexps
    elements = tree.map { |t| build_ast(t) }.compact
    SexpList.new(elements)
  when Hash
    # Try to find the actual sexp value
    if tree[:sexp]
      build_ast(tree[:sexp])
    elsif tree[:list]
      build_ast(tree[:list])
    elsif tree[:elements]
      build_ast(tree[:elements])
    elsif tree[:atom]
      build_ast(tree[:atom])
    else
      # Just use the raw string
      s = tree.to_s
      if s.match?(/^-?\d+(\.\d+)?$/)
        SexpNumber.new(s)
      else
        SexpSymbol.new(s)
      end
    end
  else
    # Treat as string
    s = tree.to_s
    if s.match?(/^-?\d+(\.\d+)?$/)
      SexpNumber.new(s)
    else
      SexpSymbol.new(s)
    end
  end
end

# Example usage
if __FILE__ == $PROGRAM_NAME
  puts '=' * 60
  puts 'S-Expression Parser - RubyTransform'
  puts '=' * 60
  puts

  test_cases = [
    '42',
    'hello',
    '(+ 1 2)',
    '(+ 1 (* 2 3))',
    '(list 1 2 3)',
    '()'
  ]

  test_cases.each do |input|
    puts '-' * 40
    puts "Input: #{input}"
    begin
      parse_sexp(input)
    rescue StandardError => e
      puts "Error: #{e.message}"
    end
    puts
  end
end
