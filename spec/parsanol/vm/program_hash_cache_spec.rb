# frozen_string_literal: true

require "spec_helper"

# rs#166: the program cache is structure-hash-keyed in addition to
# atom identity, so fresh parser instances (or rules called on them)
# share the compiled program instead of silently recompiling the
# entire grammar per call — the fresh-parser recompile trap that
# cost coradoc 25x on table transforms (metanorma/coradoc#265).
RSpec.describe "VM program structure-hash cache" do
  def build_grammar_class
    Class.new(Parsanol::Parser) do
      rule(:word) { match("[a-z]").repeat(1).as(:w) }
      rule(:sep) { str(",") }
      rule(:list) { (word >> (sep >> word).repeat).as(:l) }
      root :list
    end
  end

  it "shares one compiled program across fresh parser instances" do
    first = build_grammar_class.new
    second = build_grammar_class.new

    program_one = nil
    program_two = nil
    Parsanol::VM.instance_exec do
      clear_program_cache
      program_one = program_for(first.root)
      program_two = program_for(second.root)
    end

    expect(program_one).not_to be_nil
    expect(program_two).to equal(program_one)
  end

  it "parses identically through a fresh instance after another parsed" do
    first = build_grammar_class.new
    second = build_grammar_class.new

    expect(first.parse("a,b,c")).to eq(second.parse("a,b,c"))
  end
end
