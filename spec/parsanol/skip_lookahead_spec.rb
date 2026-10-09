# frozen_string_literal: true

require "spec_helper"

# parsanol-ruby#192: trivia injection must not descend into (or land
# directly before) lookaheads — a lookahead's contract is the RAW next
# character. An injected separator between a keyword and its absent?
# boundary check made the check examine the identifier's first
# character instead of the separator, so every keyword-prefixed input
# failed to parse under skip.
RSpec.describe "skip injection and lookaheads" do
  def keyword_parser_class
    Class.new(Parsanol::Parser) do
      rule(:trivia) { match[" \r\n\t\f"].repeat(1) }
      rule(:kw) { (str("SCHEMA") >> match["a-zA-Z0-9_"].absent?).as(:kw) }
      rule(:ident) { match["a-zA-Z"].repeat(1).as(:ident) }
      rule(:doc) { (kw >> ident >> str(";") >> str("END") >> str(";")).as(:doc) }
      skip(:trivia, whitespace: :space)
      root(:doc)

      def self.name
        "SkipLookahead"
      end
    end
  end

  it "keeps keyword boundary checks on the raw next character" do
    tree = keyword_parser_class.new.parse("SCHEMA test;END;")
    expect(tree[:doc][:kw].to_s).to eq("SCHEMA")
    expect(tree[:doc][:ident].to_s).to eq("test")
  end

  it "parses identically on both engines" do
    skip "native engine unavailable" unless Parsanol::Native.available?

    input = "SCHEMA test;END;"
    ruby_tree = keyword_parser_class.new.parse(input, mode: :ruby)
    native_tree = keyword_parser_class.new.parse(input, mode: :native)
    expect(native_tree).to eq(ruby_tree)
  end

  it "still skips separator trivia around the keyword" do
    tree = keyword_parser_class.new.parse("  SCHEMA  test;END;")
    expect(tree[:doc][:ident].to_s).to eq("test")
  end
end
