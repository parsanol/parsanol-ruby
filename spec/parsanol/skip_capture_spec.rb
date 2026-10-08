# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#180: the Ruby-DSL skip surface gains trivia capturers —
# `skip :trivia, capture: { rule => kind }` wraps the injected trivia in
# a TriviaCapture (the PARG `skip = trivia capture: comments` shape):
# units matching a capturer's leading literal attach to the next Named
# capture under `comments:`; whitespace-shaped units never record;
# captures never join span captures.
RSpec.describe "DSL skip capturers" do
  def capture_parser_class(captures)
    Class.new(Parsanol::Parser) do
      rule(:spaces) { match(/[ \t\n]/).repeat(1) }
      rule(:line_comment) { str("//") >> match(/[^\n]/).repeat }
      rule(:block_comment) { str("/*") >> (str("*/").absent? >> match(/./m)).repeat >> str("*/") }
      # The PARG idiom: the skip rule repeats whole units, so one
      # wrapper application consumes every consecutive comment/space
      # run up to the next terminal.
      rule(:trivia) { (spaces | line_comment | block_comment).repeat(1) }
      rule(:word) { match(/[a-z]/).repeat(1).as(:word) }
      rule(:list) { (word.as(:item) >> (str(",") >> word.as(:item)).repeat).as(:list) }
      skip :trivia, capture: captures
      root :list

      def self.name
        "DslSkipCapture"
      end
    end
  end

  it "attaches a line comment to the capture it precedes" do
    tree = capture_parser_class(line_comment: :line_comment).new
      .parse("alpha, // intro\nbeta")
    second = tree[:list][1][:item]
    expect(second[:comments]).to eq([{ line_comment: "// intro" }])
    # and the first item has no comments channel
    expect(tree[:list][0][:item]).not_to have_key(:comments)
  end

  it "attaches block comments under their own kind" do
    tree = capture_parser_class(block_comment: :block).new
      .parse("alpha, /* intro */ beta")
    expect(tree[:list][1][:item][:comments]).to eq([{ block: "/* intro */" }])
    expect(tree[:list][0][:item]).not_to have_key(:comments)
  end

  it "never records whitespace-shaped units" do
    tree = capture_parser_class(line_comment: :line_comment).new
      .parse("alpha , beta")
    expect(tree.inspect).not_to include("comments")
  end

  it "discards comments without a capture declaration" do
    plain = capture_parser_class(nil)
    tree = plain.new.parse("alpha // note\n, beta")
    expect(tree.inspect).not_to include("comments")
    expect(tree[:list][0][:item][:word].to_s).to eq("alpha")
    expect(tree[:list][1][:item][:word].to_s).to eq("beta")
  end

  it "matches the native engine tree for parity" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    input = "alpha, // intro\nbeta"
    parser = capture_parser_class(line_comment: :line_comment)
    ruby_tree = parser.new.parse(input, mode: :ruby)
    native_tree = parser.new.parse(input, mode: :native)
    expect(native_tree).to eq(ruby_tree)
    expect(native_tree.inspect).to include("// intro")
  end

  it "raises for a capturer without a leading literal" do
    expect { capture_parser_class(word: :word).new.parse("alpha") }
      .to raise_error(Parsanol::GrammarError, /word.*no leading literal/m)
  end
end
