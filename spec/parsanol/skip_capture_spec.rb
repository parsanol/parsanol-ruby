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

  # Units are positioned Slices on both engines — source replay (the
  # point of whitespace mode) reads the offset, and the recorded text
  # must be the input slice at that offset: trimmed marker text starts
  # after the unit's leading whitespace, not at the wrapper.
  it "records marker and whitespace units at their true offsets on both engines" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    parser = capture_parser_class(line_comment: :line)
    tree = parser.new.parse("alpha, // intro\nbeta")
    unit = tree[:list][1][:item][:comments].first
    expect(unit[:line].offset).to eq(7)
    expect(unit[:line].content).to eq("// intro")
    expect("alpha, // intro\nbeta"[7, 8]).to eq("// intro")
  end

  # A Named whose value is a repetition of hashes (decl.repeat.as)
  # keeps the hash items unwrapped even when a trivia attachment makes
  # the Named hash multi-key — the single-key path already kept them,
  # and the engines must agree (the native side double-wrapped every
  # element under the repetition name).
  it "keeps named-repetition items unwrapped under a trivia attachment" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    klass = Class.new(Parsanol::Parser) do
      rule(:spaces) { match(/[ \t\n]/).repeat(1) }
      rule(:simple_id) { match(/[a-z]/).repeat(1).as(:id) }
      rule(:decl) { str("x").as(:dx) >> str(",").maybe }
      rule(:body) { decl.repeat.as(:items).as(:body) }
      rule(:doc) do
        str("schema").as(:tSCHEMA) >> simple_id.as(:sid) >> str(";") >>
          body >> str("end").as(:tEND) >> str(";")
      end
      skip :spaces, whitespace: :space
      root :doc

      def self.name
        "DslSkipAttachRepetition"
      end
    end
    input = "schema a; x end;"
    parser = klass.new
    ruby_tree = parser.parse(input, mode: :ruby)
    native_tree = parser.parse(input, mode: :native)
    expect(native_tree).to eq(ruby_tree)
    expect(ruby_tree[:body][:items].first).to have_key(:dx)
    expect(ruby_tree[:body][:items].first).not_to have_key(:items)
  end

  # Keyword ladders drain pending units through empty-matching Named
  # captures inside branches that later fail: the unit must survive
  # the failed branch (Named snapshot/restore) and attach exactly
  # once, at its true offset, on both engines (the native side used
  # to lose the unit to a truncate-only rollback).
  it "survives keyword ladders that drain through failed branches" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    klass = Class.new(Parsanol::Parser) do
      rule(:spaces) { match(/[ \t\n]/).repeat(1) }
      rule(:own_spaces) { match(/[ \t]/).repeat(0).as(:own) }
      rule(:kw_abs) { (own_spaces >> str("ABS")).as(:kw) }
      rule(:word) { match(/[a-z]/).repeat(1).as(:w) }
      rule(:stmt) { (kw_abs | word).as(:stmt) }
      rule(:doc) { stmt >> str(";").as(:semi) }
      skip :spaces, whitespace: :space
      root :doc

      def self.name
        "DslSkipKeywordLadder"
      end
    end
    input = " alpha;"
    parser = klass.new
    ruby_tree = parser.parse(input, mode: :ruby)
    native_tree = parser.parse(input, mode: :native)
    expect(native_tree).to eq(ruby_tree)
    # the unit drained into the empty own_spaces inside the failed
    # kw branch comes back and attaches to the successful word capture
    comments = ruby_tree[:stmt][:comments]
    expect(comments).to eq([{ space: " " }])
    expect(comments.first[:space].offset).to eq(0)
    expect(ruby_tree[:semi]).to be_a(Parsanol::Slice)
  end
end
