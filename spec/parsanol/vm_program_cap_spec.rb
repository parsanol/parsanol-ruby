# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#147: the VM compiler's oversize check ran only AFTER the
# full inline build. A grammar whose inlined size explodes (cross-
# referencing rules under skip injection — LML reached 6.3M instructions
# / 16M with subroutines) paid minutes of compile time and gigabytes of
# transient allocations for a program that was then discarded and
# rebuilt non-inlined. Emission now aborts at the cap; the non-inline
# retry is O(atoms).
describe "VM program cap" do
  it "aborts an exploding inline build at the cap and compiles non-inlined" do
    parser_class = Class.new(Parsanol::Parser) do
      rule(:r0) { str("a") }
      (1..16).each do |i|
        prev = :"r#{i - 1}"
        define_method("rule_r#{i}") { send(prev) >> send(prev) }
        rule(:"r#{i}") { send("rule_r#{i}") }
      end
      root(:r16)
    end

    # r16 = 2^16 'a's; inlining doubles each level (65k instructions —
    # past the 40k cap), so the inline pass must abort early and the
    # non-inline build must serve the parse.
    input = "a" * (2**16)
    result = parser_class.new.parse(input)
    expect(result.to_s.length).to eq(input.length)
  end

  it "surrenders a grammar beyond the cap even non-inlined to the interpreter" do
    stub_const("Parsanol::VM::Compiler::MAX_PROGRAM", 4)

    parser_class = Class.new(Parsanol::Parser) do
      rule(:pair) { match(/[_a-z0-9]/).repeat(1).as(:k) >> str("=") >> match(/[0-9]/).repeat(1).as(:v) }
      rule(:document) { (pair >> str("\n")).repeat(1) }
      root(:document)
    end

    tree = parser_class.new.parse("k1=1\nk2=2\n", mode: :ruby)
    expect(tree).to eq([{ k: "k1", v: "1" }, { k: "k2", v: "2" }])
  end
end
