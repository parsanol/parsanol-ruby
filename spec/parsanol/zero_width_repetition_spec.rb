# frozen_string_literal: true

require "spec_helper"
require "timeout"

# A repetition body that succeeds without consuming input cannot make
# progress; both engines count the empty match and stop iterating (the
# min check applies as usual). Before this guard the interpreter looped
# forever and the VM burned its step budget before bailing.
RSpec.describe "zero-width repetition guard" do
  def paren_parser_class
    Class.new(Parsanol::Parser) do
      # Digit first: ordered choice would otherwise commit to the
      # empty-matching paren branch and never try the digit.
      rule(:expr)     { match(/[0-9]/) | (str("(") >> expr >> str(")")).maybe }
      rule(:document) { expr.repeat(1) >> str("!") }
      root(:document)
    end
  end

  def engine_tree(parser, input, vm_enabled:)
    Parsanol::VM.disable_for!(parser) unless vm_enabled
    parser.parse(input, mode: :ruby)
  end

  it "terminates linearly on both engines and agrees with the interpreter" do
    input = "(((7)))!"

    vm_tree = engine_tree(paren_parser_class.new, input, vm_enabled: true)
    interp_tree = engine_tree(paren_parser_class.new, input, vm_enabled: false)

    expect(strip_positions(vm_tree)).to eq(strip_positions(interp_tree))
  end

  it "fails linearly when the trailing matcher is absent (no hang)" do
    parser = paren_parser_class.new

    expect do
      Timeout.timeout(10) { parser.parse("(((7)))", mode: :ruby) }
    end.to raise_error(Parsanol::ParseFailed)
  end

  it "counts the empty match: unbounded repeat(2) of an empty-matching body fails, repeat(1) succeeds" do
    build = lambda do |min|
      Class.new(Parsanol::Parser) do
        rule(:document) { str("a").maybe.repeat(min) }
        root(:document)
      end
    end

    expect do
      Timeout.timeout(10) { build.call(2).new.parse("", mode: :ruby) }
    end.to raise_error(Parsanol::ParseFailed)

    expect { build.call(1).new.parse("", mode: :ruby) }.not_to raise_error
  end

  it "keeps consuming repetitions unaffected (regression guard)" do
    parser_class = Class.new(Parsanol::Parser) do
      rule(:document) { match(/[a-z]/).repeat(1) }
      root(:document)
    end

    parser = parser_class.new
    expect(parser.parse("abc", mode: :ruby).to_s).to eq("abc")
  end
end
