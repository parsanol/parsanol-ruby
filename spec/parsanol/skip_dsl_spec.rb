# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#134/#152 DSL surface: `skip :rule` on a Parser
# subclass injects optional trivia before every terminal of the root's
# rule tree, with leading/trailing skips at the entry — the same
# semantics the PARG compiler bakes into artifacts.
RSpec.describe "skip DSL" do
  def skipper_class
    Class.new(Parsanol::Parser) do
      rule(:spaces) { match(/[ \t\n]/).repeat(1) }
      rule(:comment) { str("//") >> match(/[^\n]/).repeat }
      rule(:trivia) { (spaces | comment).repeat(1) }
      rule(:left) { match(/[a-z]/).repeat(1).as(:l) }
      rule(:right) { match(/[0-9]/).repeat(1).as(:r) }
      rule(:doc) { (left >> str("=") >> right).as(:assign) }
      skip :trivia
      root :doc
    end
  end

  it "consumes leading, inter-token and trailing trivia" do
    tree = skipper_class.new.parse(" a = 1 ", mode: :ruby)
    expect(tree[:assign][:l].to_s).to eq("a")
    expect(tree[:assign][:r].to_s).to eq("1")
  end

  it "consumes comment trivia between tokens" do
    tree = skipper_class.new.parse(" a // note\n= 1", mode: :ruby)
    expect(tree[:assign][:l].to_s).to eq("a")
    expect(tree[:assign][:r].to_s).to eq("1")
  end

  it "parses with identical structure without trivia present" do
    bare = skipper_class.new.parse("a=1", mode: :ruby)
    spaced = skipper_class.new.parse(" a = 1 ", mode: :ruby)
    strip = ->(t) { t.inspect.gsub(/@\d+/, "") }
    expect(strip.call(bare)).to eq(strip.call(spaced))
  end

  it "rejects a nullable skip rule at first parse" do
    klass = Class.new(Parsanol::Parser) do
      rule(:maybe_x) { str("x").maybe }
      rule(:doc) { str("a") }
      skip :maybe_x
      root :doc
    end
    expect { klass.new.parse("a", mode: :ruby) }
      .to raise_error(Parsanol::GrammarError, /non-nullable/)
  end

  it "is order-independent with root" do
    klass = Class.new(Parsanol::Parser) do
      root :doc
      rule(:spaces) { match(" ").repeat(1) }
      rule(:word) { match(/[a-z]/).repeat(1).as(:w) }
      rule(:doc) { word }
      skip :spaces
    end
    expect(klass.new.parse(" abc ", mode: :ruby)[:w].to_s).to eq("abc")
  end

  # parsanol-ruby#190: the injector used to inline rule bodies at every
  # referencing site, so rendering any injected atom (to_s, and failure
  # messages built from inspect) expanded the grammar exponentially —
  # a cross-referencing grammar's first failing parse built a
  # multi-gigabyte message and died. Rule references stay Entities:
  # the render is name-based and linear.
  it "renders and fails linearly on cross-referencing injected grammars" do
    klass = Class.new(Parsanol::Parser) do
      rule(:spaces) { match(/[ \t]/).repeat(1) }
      rule(:word) { match(/[a-z]/).repeat(1).as(:w) }
      rule(:tail) { (str(",") >> item).maybe }
      rule(:item) { word >> tail }
      rule(:doc) { str("[") >> item >> str("]") }
      skip :spaces
      root :doc
    end
    parser = klass.new
    expect(parser.root.to_s).to eq("DOC")
    expect(parser.parse(" [ a ] ", mode: :ruby)[:w].to_s).to eq("a")
    # the failing parse builds a failure message from the injected tree
    # without exponential expansion
    expect { parser.parse("[ a ,", mode: :ruby) }
      .to raise_error(Parsanol::ParseFailed)
  end
end
