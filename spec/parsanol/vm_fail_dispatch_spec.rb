# frozen_string_literal: true

require "spec_helper"

# The executor signals terminal failure by jumping to pc = FAIL, which the
# dispatch case must land on a dedicated program slot (GH-regression from
# ab1a17b: the landing was checked against an arbitrary operand slot, so
# every terminal failure BAILed and sticky-disabled the VM for the grammar
# — silently routing all repeat-terminated parses to the interpreter).
RSpec.describe "VM FAIL dispatch and memoization seeding" do
  def kv_parser_class
    Class.new(Parsanol::Parser) do
      rule(:ident)    { match(/[_a-z0-9]/).repeat(1) }
      rule(:num)      { match(/[0-9]/).repeat(1) }
      rule(:pair)     { ident.as(:k) >> str("=") >> num.as(:v) >> str(";") >> str("\n") }
      rule(:document) { pair.repeat }
      root(:document)
    end
  end

  it "keeps the VM enabled after a parse whose repetition ends by terminal failure" do
    parser = kv_parser_class.new
    input = (1..5).map { |i| "key#{i}=#{i};\n" }.join

    expect(parser.parse(input, mode: :ruby).size).to eq(5)

    program = Parsanol::VM.program_for(parser.root)
    expect(program).not_to be_nil
    expect(program).not_to eq(:fallback)
  end

  it "keeps the VM enabled after a failing parse" do
    parser = kv_parser_class.new

    expect { parser.parse("key=;\n", mode: :ruby) }.to raise_error(Parsanol::ParseFailed)

    program = Parsanol::VM.program_for(parser.root)
    expect(program).not_to eq(:fallback)
  end

  it "produces interpreter-identical trees across separate VM-enabled parses" do
    input = (1..20).map { |i| "key#{i}=#{i};\n" }.join

    trees = Array.new(2) do
      parser = kv_parser_class.new
      parser.parse(input, mode: :ruby)
    end
    expect(trees[0]).to eq(trees[1])
  end

  context "with compile-time structure-seeded memoization" do
    # The flag can only be present after the first parse if compile-time
    # structure analysis seeded it: this input is far too small to flip the
    # runtime heavy detection (budget bust / step-density).
    it "seeds memoization for the first parse of a grammar containing repeat/maybe" do
      parser_class = Class.new(Parsanol::Parser) do
        rule(:pair)     { match(/[_a-z0-9]/).repeat(1).as(:k) >> str("=") >> match(/[0-9]/).repeat(1).as(:v) }
        rule(:document) { (pair >> str("\n")).repeat(1) }
        root(:document)
      end

      parser = parser_class.new
      parser.parse("k1=1\nk2=2\n", mode: :ruby)

      heavy = Parsanol::VM.instance_variable_get(:@heavy) || {}
      # rubocop:disable-next Lint/HashCompareByIdentity -- mirrors the VM's object_id-keyed heavy flag
      expect(heavy[parser.root.object_id]).to be(true)
    end

    it "leaves grammars without repetition unseeded" do
      parser_class = Class.new(Parsanol::Parser) do
        rule(:document) { str("hello") >> str(" ") >> str("world") }
        root(:document)
      end

      parser = parser_class.new
      parser.parse("hello world", mode: :ruby)

      heavy = Parsanol::VM.instance_variable_get(:@heavy) || {}
      # rubocop:disable-next Lint/HashCompareByIdentity -- mirrors the VM's object_id-keyed heavy flag
      expect(heavy[parser.root.object_id]).to be_falsey
    end
  end
end
