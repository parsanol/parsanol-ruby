# frozen_string_literal: true

require "spec_helper"

# GH-68: a grammar whose compiled program crashes the Ruby VM executor
# (ArgumentError from nil operands) must fall back to the interpreter
# instead of raising.
RSpec.describe "VM crash fallback" do
  it "parses via the interpreter when the executor crashes" do
    parser = Class.new(Parsanol::Parser) do
      rule(:line_char)     { match["^\\r\\n"] }
      rule(:line_ending)   { match["\\r\\n"].repeat(1) }
      rule(:line_verbatim) { line_char.repeat(1).as(:ln) >> line_ending | line_char.repeat(1).as(:ln) }
      rule(:document)      { line_verbatim.repeat(1) }
      root(:document)
    end

    expect { parser.new.parse("[source,ruby]\nputs 1\n", mode: :ruby) }
      .not_to raise_error
  end
end
