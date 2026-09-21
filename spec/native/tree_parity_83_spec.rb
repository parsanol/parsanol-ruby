# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#83: native tree shape must match the Ruby engine for
# the coradoc paragraph pattern — a named repetition of one hash must
# stay an Array under the capture key, not collapse to a bare Hash.
# The SSOT is Parslet::Atoms::CanFlatten; the native transformer is an
# exact port of that fold.
RSpec.describe "native tree parity (#83)", :native do
  before do
    skip "Native extension not available" unless Parsanol::Native.available?
  end

  def parity(parser, input)
    ruby = parser.parse(input, mode: :ruby)
    native = parser.parse(input, mode: :native)
    expect(native.inspect).to eq(ruby.inspect)
    native
  end

  it "keeps a single-item named repetition as an array under :lines" do
    # Minimal form of coradoc's paragraph_text_line.repeat.as(:lines)
    g = Class.new(Parsanol::Parser) do
      rule(:text) { match(/[^\n]/).repeat(1).as(:text) }
      rule(:lb) { str("\n").as(:line_break) }
      rule(:line) { text >> lb }
      rule(:doc) { line.repeat(1).as(:lines) }
      root(:doc)
    end.new

    tree = parity(g, " image::pic.png[caption, 200]\n")
    expect(tree[:lines]).to be_a(Array)
    expect(tree[:lines].length).to eq(1)
    expect(tree[:lines][0]).to be_a(Hash)
    expect(tree[:lines][0].keys).to contain_exactly(:text, :line_break)
  end

  it "keeps the array when an empty trailing maybe rides alongside the repetition" do
    # The exact shape that collapsed under the pre-#83 heuristic:
    # sequence = [repetition_of_one_hash, empty_maybe] under .as(:lines)
    g = Class.new(Parsanol::Parser) do
      rule(:text) { match(/[^\n]/).repeat(1).as(:text) }
      rule(:lb) { str("\n").as(:line_break) }
      rule(:line) { text >> lb }
      rule(:doc) do
        (line.repeat(1) >> (line.repeat(1, 1) >> str("").maybe).repeat(0, 1))
          .as(:lines)
      end
      root(:doc)
    end.new

    tree = parity(g, " image::pic.png[caption, 200]\n")
    expect(tree[:lines]).to be_a(Array)
    expect(tree[:lines].length).to eq(1)
  end

  it "does not hoist a named sequence into an Array when an empty trailing rep is present" do
    # Paragraph-shaped: named sequence of [header?, lines_hash, trailing_rep]
    g = Class.new(Parsanol::Parser) do
      rule(:text) { match(/[^\n]/).repeat(1).as(:text) }
      rule(:lb) { str("\n").as(:line_break) }
      rule(:line) { text >> lb }
      rule(:lines) { line.repeat(1).as(:lines) }
      rule(:trailing) { str("\n").repeat(0) }
      rule(:paragraph) { (lines >> trailing).as(:paragraph) }
      root(:paragraph)
    end.new

    tree = parity(g, "hello\n")
    expect(tree[:paragraph]).to be_a(Hash)
    expect(tree[:paragraph][:lines]).to be_a(Array)
  end

  it "preserves multi-item repetitions as arrays" do
    g = Class.new(Parsanol::Parser) do
      rule(:text) { match(/[^\n]/).repeat(1).as(:text) }
      rule(:lb) { str("\n").as(:line_break) }
      rule(:line) { text >> lb }
      rule(:doc) { line.repeat(1).as(:lines) }
      root(:doc)
    end.new

    tree = parity(g, "one\ntwo\nthree\n")
    expect(tree[:lines]).to be_a(Array)
    expect(tree[:lines].length).to eq(3)
  end
end
