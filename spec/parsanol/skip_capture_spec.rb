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
      rule(:sep_item) { str(",") >> word.as(:item) }
      rule(:list) { (word.as(:item) >> sep_item.repeat(1)).as(:list) }
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

  # parsanol-ruby#180: the source-preserving mode — units matching no
  # capturer record verbatim under the declared whitespace kind, in
  # order, so a concatenator can replay the full trivia stream. The
  # specs use shapes where trivia precedes a capture directly (the
  # attachment around separators is the open divergence on the issue).
  def whitespace_parser_class
    Class.new(Parsanol::Parser) do
      rule(:spaces) { match(/[ \t\n]/).repeat(1) }
      rule(:line_comment) { str("//") >> match(/[^\n]/).repeat }
      rule(:trivia) { (spaces | line_comment).repeat(1) }
      rule(:word) { match(/[a-z]/).repeat(1).as(:word) }
      rule(:sep_item) { str(",") >> word.as(:item) }
      rule(:list) { (word.as(:item) >> sep_item.repeat(1)).as(:list) }
      skip :trivia, capture: { line_comment: :line }, whitespace: :space
      root :list

      def self.name
        "DslSkipWhitespace"
      end
    end
  end

  def kinds(comments)
    comments.map { |h| h.transform_values(&:to_s) }
  end

  it "records whitespace units verbatim under the whitespace kind" do
    tree = whitespace_parser_class.new.parse("alpha, beta")
    expect(kinds(tree[:list][1][:item][:comments])).to eq([{ space: " " }])
    expect(tree[:list][0][:item]).not_to have_key(:comments)
  end

  it "keeps remark and whitespace kinds distinct" do
    tree = whitespace_parser_class.new.parse("alpha, // intro\nbeta")
    expect(kinds(tree[:list][1][:item][:comments]))
      .to eq([{ line: "// intro" }])
    expect(tree[:list][0][:item]).not_to have_key(:comments)
  end

  it "matches the native engine tree for whitespace parity" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    input = "alpha, beta"
    parser = whitespace_parser_class
    ruby_tree = parser.new.parse(input, mode: :ruby)
    native_tree = parser.new.parse(input, mode: :native)
    expect(native_tree).to eq(ruby_tree)
    expect(native_tree.inspect).to include("space")
  end

  # The d54a29e refinement case: trivia consumed around a separator
  # inside a repetition attaches consistently across engines — the
  # unit before the "," drains into the FOLLOWING capture on both.
  it "attaches separator-adjacent trivia identically across engines" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    parser = whitespace_parser_class
    input = "alpha , beta"
    ruby_tree = parser.new.parse(input, mode: :ruby)
    native_tree = parser.new.parse(input, mode: :native)
    expect(native_tree).to eq(ruby_tree)
    # Both the pre- and post-comma runs drain into the following
    # capture (leading attachment) — on both engines.
    expect(kinds(native_tree[:list][1][:item][:comments]))
      .to eq([{ space: " " }, { space: " " }])
    expect(native_tree[:list][0][:item]).not_to have_key(:comments)
  end
end
